# Data Model

## Overview

The synced schema contains exactly **two entities**: `TaskRecord` and `TimerEventRecord`. A separate, non-mirrored staging container holds WC-received events (see `ICLOUD_SYNC.md` §16).

This frozen two-entity schema is the product of deliberate constraint analysis. The CloudKit contract (plan §13, §14) requires:
- All properties optional or defaulted
- No `@Attribute(.unique)` anywhere
- No CloudKit relationships anywhere
- Private database only

These are not limitations to work around — they are the contract, and the architecture is designed to work within them (plan §14).

---

## TaskRecord

The persistence model for tasks. Maps 1:1 to the `Task` domain model via `AppData` repositories.

| Field | Type | Notes |
|---|---|---|
| `id` | `UUID?` | Primary identifier. `AppData`'s `TaskMapping` coalesces `nil` to a fresh `UUID()`, which cannot happen for a record that has ever round-tripped through `upsert`. |
| `title` | `String?` | Required, non-empty after trimming, at the domain layer. Coalesces to `""`. |
| `notes` | `String?` | Optional. |
| `createdAt` | `Date?` | When the task was created. Coalesces to `.distantPast`. |
| `completedAt` | `Date?` | `nil` when incomplete. Completion is derived: `completedAt != nil` (plan §9). |
| `scheduledDay` | `String?` | ISO `yyyy-MM-dd` day key, or `nil` for Pool (plan §9). |
| `priority` | `Int?` | Raw `TaskPriority` (`0` none … `3` high). `nil` coalesces to `.none`. |
| `updatedAt` | `Date?` | Last modification timestamp. Monotonic per device. Coalesces to `.distantPast`. |

### CloudKit constraints

- **Every stored property on the `@Model` is genuinely `Optional` (`?`), not just optional-or-defaulted
  at the Swift `init` level.** SwiftData's CloudKit mirroring validation checks true Optionality in
  the generated schema; a non-optional property with only a Swift init default (`id: UUID = UUID()`)
  still fails the contract at `ModelContainer` construction time with `SwiftDataError.loadIssueModelContainer`
  — this shipped broken from Milestone 3 through Milestone 5 because the app was only ever run against
  `makeLocalInMemory()` until 2026-08-14, when actually launching against `.makeSynced()` for the first
  time crashed immediately. Fixed 2026-08-14; see `memory.md`. The domain-facing `Task` struct stays
  non-optional — `TaskMapping.toDomain` coalesces every `nil` to the same default the old Swift
  init used.
- No unique attributes (CloudKit sync does not support `@Attribute(.unique)`).
- No relationships to `TimerEventRecord` — associations are UUID fields resolved in `AppData` (plan §11, §14).

### Association to timer events

The link between tasks and timer sessions is expressed as `TimerEventRecord.relatedTaskID: UUID?` on the timer side. There is no reverse link from `TaskRecord` to timer events. Per-task totals (F9) are computed by querying timer events by `relatedTaskID` and projecting each session (plan §11, §28). Manual corrections use synced `TaskTimeAdjustmentRecord` / `TaskSessionExclusionRecord` — never by mutating timer events.

---

## TaskTimeAdjustmentRecord

Manual time added to a task’s spent total. Synced; CloudKit-safe optionals.

| Field | Type | Notes |
|---|---|---|
| `id` | `UUID?` | Adjustment identity. |
| `taskID` | `UUID?` | Soft link to `TaskRecord.id`. |
| `durationSeconds` | `Double?` | Positive duration contributed to the total. |
| `note` | `String?` | Optional user note. |
| `occurredAt` | `Date?` | When the work is attributed. |
| `createdAt` / `updatedAt` | `Date?` | Audit timestamps. |

## TaskSessionExclusionRecord

Hides one projected timer session from a task’s log total without deleting events.

| Field | Type | Notes |
|---|---|---|
| `id` | `UUID?` | Exclusion identity. |
| `taskID` | `UUID?` | Soft link to the task. |
| `sessionID` | `UUID?` | Soft link to the timer session. |
| `createdAt` | `Date?` | When excluded. |

---

## TimerEventRecord

The persistence model for timer events. Maps 1:1 to the `TimerEvent` domain model via `AppData` repositories.

| Field | Type | Notes |
|---|---|---|
| `id` | `UUID?` | Primary identifier. Deduplication key (plan §10, §28). Coalesces to a fresh `UUID()`. |
| `sessionID` | `UUID?` | Groups events into sessions. All events in one session share this ID. Coalesces to a fresh `UUID()`. |
| `kind` | `String?` | Event kind as a string, not enum raw value. Unknown kinds are skipped, never deleted (plan §10). Coalesces to `""`. |
| `occurredAt` | `Date?` | UTC timestamp of when the event occurred. Coalesces to `.distantPast`. |
| `deviceID` | `UUID?` | Identifies the authoring device. Final tiebreak in arbitration (plan §20). Coalesces to a fresh `UUID()`. |
| `lamport` | `Int?` | Lamport counter, stamped at authoring time. Encodes causality within a session (plan §10). Coalesces to `0`. |
| `schemaVersion` | `Int?` | Schema version of the authoring build. Forward compatibility marker (plan §10). Coalesces to `0`. |
| `duration` | `Double?` | Duration in seconds. Only present on `.started` events. Immutable for the session's lifetime. |
| `relatedTaskID` | `UUID?` | Optional task reference. Only present on `.started` events. Immutable for the session's lifetime. |

### Event kinds (persisted as strings)

| Kind | Meaning |
|---|---|
| `"started"` | Session begun. Only event carrying `duration` and `relatedTaskID`. |
| `"paused"` | Active session paused. |
| `"resumed"` | Paused session resumed. |
| `"stopped"` | User-ended session. Retains history. |
| `"reset"` | User-discarded session. History discarded. |

There is deliberately no `"finished"` kind — expiry is derived, never an event (plan §10, §18).

### CloudKit constraints

- All properties are genuinely `Optional` at the `@Model` level — same contract as `TaskRecord`,
  see its "CloudKit constraints" note above (plan §13).
- No unique attributes. Deduplication by `id` is handled in the fold (plan §10).
- No relationships to `TaskRecord`. The `relatedTaskID` is a plain UUID.

---

## Associations as Plain UUID Fields

The two entities are associated through a plain UUID, not a CloudKit relationship:

```
TimerEventRecord.relatedTaskID → TaskRecord.id
```

This is a soft reference — referential integrity is deliberately not enforced. A deleted task leaves timer sessions with a dangling UUID; the join in `AppData` resolves it to "Deleted task" for display (plan §11).

**Why not a CloudKit relationship.** CloudKit relationships are the most fragile construct in the SwiftData+CloudKit stack. They add migration complexity, failure modes, and constraint issues that a UUID field avoids entirely (plan §3, §14).

---

## Index Definitions

### `#Index(kind, occurredAt, deviceID)` on TimerEventRecord

**Serves:** Q1 — the session-start index. Fetch `kind == "started"`, sorted by `(occurredAt ascending, deviceID ascending)`. Yields a small, totally-ordered list of `(sessionID, startedAt, deviceID)` — one entry per session ever started. The last entry is the active session (the §20 maximum). For a `.started` event, `occurredAt` *is* its `startedAt`, so no separate field is needed (plan §28).

### `#Index(sessionID)` on TimerEventRecord

**Serves:** Q2 — projection. Fetch all events for a target session. A handful of rows per session. Combined with the supersession boundary from Q1, this provides the complete input for `TimerProjection.project(events, supersededAt:)` (plan §28).

### What the indexes do NOT serve

- Per-task totals (F9) query `.started` events by `relatedTaskID` to obtain session IDs, then project each. This is not indexed separately in MVP — if it profiles slow, the cache is local-only and never synced (plan §12, §28).
- Task queries use SwiftData's default indexing on `id` and any indexed properties specified in the `@Model` annotation.

---

## Sync Metadata

CloudKit manages sync metadata automatically via SwiftData's mirroring. No manual sync tokens, change tokens, or conflict resolution metadata are stored in the entities themselves.

- **CloudKit container:** `iCloud.com.diwan.TaskTracker`
- **Database:** Private only
- **Zone:** Single zone, single user, no sharing
- **Schema promotion:** Development → production before any release, deliberately and with a written checklist (R-8, plan §31)

---

## Migration Considerations

### Forward compatibility

- `kind` is a `String`, not an enum raw value — unknown kinds deserialise rather than failing (plan §10).
- `schemaVersion` accompanies every event — newer events are skipped, never deleted (plan §10).
- An older build must not destroy data it does not understand.

### Schema changes

SwiftData+CloudKit schema mistakes are expensive to undo once records exist (R-2). The mitigation:
- Freeze the two-entity schema in Milestone 0 before any `@Model` exists (plan §31).
- Every property optional or defaulted — adding new properties is safe (they default to `nil`/`0`/`false`).
- Removing properties requires careful migration testing.
- Adding new entities is additive and safe.

### iCloud account change

SwiftData tears down and rebuilds the store. Treated as a fresh device — CloudKit repopulates from the server (plan §16).

### App reinstall

CloudKit repopulates. No local backup in MVP. Accepted (plan §28).

---

## Cross-References

- `ARCHITECTURE.md` — package structure, why `AppData` owns all CloudKit contact
- `TASK_ARCHITECTURE.md` — Task domain model, DayKey, completion semantics
- `TIMER_ARCHITECTURE.md` — TimerEvent domain model, fold, state machine, arbitration
- `ICLOUD_SYNC.md` — how records sync, dual ingress, conflicts, staging store
- `TESTING.md` — persistence tests, in-memory round-trips, mapping fidelity
- `ROADMAP.md` — M3 (AppData local), M4 (convergence proof)
