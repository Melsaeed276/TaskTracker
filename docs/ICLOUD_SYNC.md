# iCloud Sync

## Chosen Persistence Architecture

**SwiftData + CloudKit private-database mirroring, for everything — with an append-only event log for timer state so the missing merge hook stops mattering** (plan §14).

- **Container:** `iCloud.com.diwan.TaskTracker`
- **Database:** Private only, single zone, single user, no sharing
- **Synced entities:** `TaskRecord` and `TimerEventRecord` (two entities only)
- **All properties optional or defaulted**, no unique attributes, no CloudKit relationships anywhere (plan §13, §14)

### Why SwiftData + CloudKit

Offline, background sync, watchOS support, and migrations for near-zero code. Its one disqualifying weakness — no custom merge hook — is neutralised by never asking it to merge anything: task edits are low-conflict and property-level LWW is genuinely fine; timer state is high-conflict and is expressed as immutable events that are appended, never updated (plan §14).

Alternatives rejected:

- **Core Data + CloudKit** — same sync engine, worse Swift 6 ergonomics, `.xcdatamodeld` in packages is awkward (plan §13).
- **CKSyncEngine / raw CloudKit** — full control, but hand-build the local store, offline queue, change-token bookkeeping, and watch path: months of infrastructure (plan §14).
- **Hybrid (SwiftData for tasks, CKSyncEngine for timer)** — two sync engines, two failure modes, two debugging stories (plan §14).
- **NSUbiquitousKeyValueStore** — latest-wins is precisely the torn-state problem we are avoiding, and it keeps no history (plan §14).

---

## Local-First Behaviour

```
User action → AppFeature controller → repository (AppData)
           → SwiftData write (local, immediate)
           → UI updates from local store
           ⋮
           → CloudKit mirroring uploads when able (background, invisible)
```

No user-facing operation ever awaits the network. The UI reads only the local store. Sync status is ambient information, never a blocker or a modal. Offline is the normal case, not an error. Everything in the offline requirement list — create, edit, complete, schedule, start, pause, resume, stop — is a local write plus, for timers, a local append (plan §15).

---

## Sync Flows

### Task changes (low-conflict)

Task edits are property-level LWW (last-writer-wins). For a single-user app editing title, notes, `completedAt`, and `scheduledDay`, property-level LWW is genuinely fine. Two devices editing different properties of the same task produce a consistent merged result. Two devices editing the same property produce a deterministic winner (latest timestamp), and neither user action is lost — the "loser" is visible in edit history if needed (plan §28).

### Timer events (high-conflict, append-only)

Timer events are immutable rows. Two devices writing concurrently produce two rows, not one torn row. The fold reconciles them as a pure function. This is why event-sourcing was chosen: SwiftData's CloudKit mirroring provides no hook for custom conflict resolution, and a mutable `ActiveTimer` row is corruptible into states that never existed. Immutable records are never merged (plan §10, §14).

### Conflict resolution

A single globally-active timer cannot be *enforced* across partitioned devices without a central authority. CloudKit provides no distributed lock. Two offline devices can each legitimately believe they started a timer. What we guarantee is that when they meet, every device reaches the *same* answer, deterministically, and that nothing is lost (plan §20).

See `TIMER_ARCHITECTURE.md` for the full arbitration rules, worked examples, and the permanent-supersession invariant.

---

## Cross-Device Timer Propagation

**Synchronised:** immutable `TimerEvent` rows — five kinds, a handful per session. **Never synchronised:** remaining time, elapsed time, or any per-second value (plan §17).

A 60-minute session with two pauses produces **five records for the entire hour**, versus 3,600 writes if remaining seconds were mirrored.

Every device projects these once, then re-runs `evaluate(at:)` locally at 1 Hz via `TimelineView`. The projection is recomputed only when the log changes; the countdown re-evaluates each tick. The display refresh touches no persistence whatsoever (plan §17).

---

## Dual-Ingress Rule

This is the most important invariant in the sync architecture. It applies when WatchConnectivity is added as a fast-path (plan §16).

### The rule

1. **Only the authoring device ever writes an event to the synced store.** This is the invariant.
2. WC-received events are inserted into a **separate, non-mirrored local staging container**, preserving the original `id`, `deviceID`, `occurredAt`, `lamport` — never re-stamped.
3. The fold reads `union(syncedStore, stagingStore)` and dedupes by `id`. The staging copy is a *faster view of the same fact*, not a second fact.
4. When the canonical row arrives via CloudKit, the staging copy is redundant and is pruned locally. Pruning the staging store is safe precisely because it is never a source of truth.
5. **WC is never a correctness dependency.** An app that ignores every WC message must converge to the identical state. This is the invariant the fake-transport tests assert (plan §16).

### Why this matters

If a WC-received event were inserted into the *synced* store, SwiftData would mirror it to CloudKit from the receiving device too, producing genuinely duplicated persistence and a second authoring device for one user action. The dual-ingress design prevents this by keeping WC events in a non-mirrored staging container (plan §16).

### Staging store details

- **Container:** Separate `ModelContainer`, NOT mirrored to CloudKit.
- **Contents:** Only WC-received `TimerEvent` records.
- **Lifecycle:** Events are pruned when the canonical row arrives via CloudKit.
- **Never a source of truth.** Only the authoring device's synced store is authoritative.

---

## Conflicts

### Task conflicts

Property-level LWW. For single-user title/notes edits, this is acceptable. Two devices editing the same field produce a deterministic winner (latest timestamp). No data is lost — the "loser" edit exists on the device that made it until overwritten by sync (plan §28).

### Timer conflicts

No conflicts in the traditional sense. Timer events are immutable and append-only. Two devices starting timers concurrently produce two `.started` events; arbitration resolves which session is active via `(startedAt, deviceID)` ordering. The loser is permanently superseded and retained as history (plan §20).

See `TIMER_ARCHITECTURE.md` for the full arbitration rule.

---

## Stale Updates

### Forward compatibility

Events with an unrecognised `kind` or a newer `schemaVersion` are skipped by the projection and never deleted from the store. An older build must not destroy data it does not understand (plan §10).

### Quarantine

A session containing any uninterpretable event is quarantined: rendered read-only with an "update required" note, and the device refuses to author `.paused` or `.resumed` into it. `.started` and `.stopped` remain authorable at all times (plan §10).

Quarantine is recomputed on every projection — never stored. When the device updates to a build that understands the unknown kind, quarantine lifts automatically. There is no quarantine flag to persist, sync, or migrate (plan §10).

---

## Retries

CloudKit handles retries automatically via SwiftData's mirroring. No manual retry logic is needed in application code. The fold is idempotent over duplicate events — CloudKit retries, re-syncs, and the WC fast-path can deliver the same logical event twice, and the fold dedupes by event `id` before folding (plan §10).

---

## Watch Sync

### CloudKit is primary

CloudKit is the primary and, in MVP, the only path. WatchConnectivity is deferred behind a measurement (plan §24).

Apple's guidance is explicit that WatchConnectivity must be *"an opportunistic optimization, rather than the primary means of supplying fresh data"* — users may never install the companion, and a paired reachable phone is not guaranteed (plan §24).

### Standalone watchOS

The watchOS app is standalone (`WKRunsIndependentlyOfCompanionApp`). The timer is shared state in iCloud and the watch can reach iCloud on its own. Requiring the phone would make the watch a worse client for no architectural gain (plan §23).

### `TimerEventTransport` seam

`AppData` defines a `TimerEventTransport` protocol with a CloudKit implementation. If spike R-1 shows CloudKit alone cannot carry the watch experience, a WatchConnectivity fast-path is an *additional* implementation, not a re-architecture (plan §16, §24).

---

## CloudKit Limitations

| Limitation | Impact | Mitigation |
| --- | --- | --- |
| No custom conflict resolution | Cannot hook into merge decisions | Event-sourcing for timers (append-only); LWW for tasks is fine |
| No `@Attribute(.unique)` | Cannot enforce unique constraints | Deduplication in the fold by event `id` |
| Fragile relationships | CloudKit relationships are migration-sensitive | Associations as plain UUID fields |
| Private database only | No shared data (acceptable — single user) | No sharing feature planned |
| Schema promotion is one-way | Mistakes are expensive once records exist | Freeze schema in M0; promote deliberately in M4 (R-8) |
| Push latency to sleeping watch | May not meet product promise for cross-device timer control | Spike R-1 measures it; WC fast-path is additive if needed (R-1) |

---

## Spike R-1 Results

**Placeholder.** Spike R-1 runs in Milestone 0 and measures three things on a floor-vs-current device
matrix (ADR 014, revised twice 2026-08-09 — floor is macOS 14 / iOS 17 / watchOS 10):

| Platform | Floor (must pass) | Current (should pass) |
| --- | --- | --- |
| macOS | 14 Sonoma | 26 Tahoe |
| iOS | 17 | 26 |
| watchOS | 10 | **26 — real hardware** (Apple Watch Series 6) |

The floor should also be verified against the real iPhone 11 (iOS 18.6.2) — the device that motivated
keeping a floor below the current-generation devices, rather than raising it to 26 everywhere.

1. **Latency:** propagation of a trivial record Mac → iPhone → Watch, foreground and background, device asleep and awake.
2. **Duplicate delivery:** whether the same record is ever observed twice after a forced resync or reinstall.
3. **Concurrent insert behaviour:** two devices inserting sibling records offline, then reconnecting — confirming that appends genuinely do not merge.

Results will be recorded here after Milestone 0 completes.

---

## Cross-References

- `ARCHITECTURE.md` — package structure, why `AppData` owns all CloudKit contact
- `DATA_MODEL.md` — `TaskRecord` and `TimerEventRecord` schemas, indexes, CloudKit constraints
- `TIMER_ARCHITECTURE.md` — how events are projected, arbitrated, and folded
- `TESTING.md` — fake transport tests, convergence assertions, staging-store pruning tests
- `ROADMAP.md` — M4 (convergence proof), spike R-1 details
