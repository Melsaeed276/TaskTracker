# TaskTracker — Architecture & Roadmap Plan (Milestone 0 Blueprint)

**Status:** Draft 6 — five Codex review rounds complete. **Cleared by review to freeze the schema and
write the ADRs**, pending user approval.
**Date:** 2026-08-09
**Toolchain verified on this machine:** Xcode 26.6 (17F113)
**Bundle prefix:** `com.diwan.TaskTracker` · **CloudKit container:** `iCloud.com.diwan.TaskTracker`
**Deployment targets:** iOS 18 · macOS 15 Sequoia · watchOS 11 — Liquid Glass applied conditionally on 26+

> **Scope.** This is the plan, not the implementation. It specifies the documentation set, package
> boundaries, and domain designs that Milestone 0 will create. No production code, no screens, no
> engine, no CloudKit code is written until this is approved.

> **Deployment floor — confirmed by the user: one generation below 26, on every platform.**
>
> | Platform | Floor (this project) | Liquid Glass release |
> |---|---|---|
> | macOS | **15 Sequoia** | 26 Tahoe |
> | iOS | **18** | 26 |
> | watchOS | **11** | 26 |
>
> Apple realigned all platform numbering on the year in 2025, so macOS went 15 → 26, iOS 18 → 26 and
> watchOS 11 → 26. There are no intermediate releases — no macOS 16–25, no iOS 19–25. "macOS 18"
> does not exist; macOS 15 Sequoia is the same-generation partner of iOS 18 and watchOS 11.
>
> Every supported OS therefore has **two appearances to support**: the floor generation (materials)
> and 26+ (Liquid Glass). See §26 and R-6.

---

## Context — why this document exists

The product is a personal task manager plus an optional, device-independent focus timer for macOS,
iOS and watchOS. Two things make it architecturally non-trivial, and both are decided here:

1. **Task and Timer are independent domains.** A naive model makes Timer a child of Task. That
   forecloses general timers, multi-session history, and independent evolution. We keep them apart.
2. **The active timer is shared logical state, not a running process.** Three devices are three views
   of one timer. Truth is timestamps synchronised through iCloud; the countdown on screen is a local
   rendering, never a synchronised value.

The second point collides with a hard platform constraint, and that collision drives the single most
important decision in this plan (§13/§14/§20).

---

## 1. Product summary

A lightweight personal productivity utility for one user across their own Apple devices.

- A durable **Pool** of tasks and ideas with no date attached.
- A focused **Today** list, assembled by pulling from the Pool or creating directly.
- An optional **focus timer** that may or may not reference a task, and which is the *same timer* on
  every device.
- macOS is the primary daily surface and lives in the menu bar. iOS is the management surface.
  watchOS is a glance-and-control surface.
- Local-first. Fully usable offline. iCloud is a synchroniser, not a dependency.

Non-goals: collaboration, accounts, backends, AI, analytics, projects, subtasks, recurrence.

## 2. Core product principles

1. **Local-first.** Every user action commits locally and returns immediately. Sync is background.
2. **Timestamps are truth.** Never synchronise a decrementing number.
3. **Immediate locally, eventually consistent remotely.** CloudKit is not realtime; the UI must never
   imply that it is.
4. **Speed over decoration.** The menu bar interaction budget is a fraction of a second.
5. **Native per platform.** Shared domain, shared design tokens — not shared layouts.
6. **No silent data loss.** Conflicts resolve deterministically, and the loser is preserved.
7. **Convergence is a property, not a hope.** Every device folding the same log must reach the same
   **projection**. Any rule that depends on the *receiving* device's identity, arrival order, or clock
   is forbidden at projection time (§10, §20). Time enters only at *evaluation*, which writes nothing
   (§18).

## 3. Task vs Timer domain separation

**What we choose.** Two independent Swift packages. `TimerDomain` references a task only as an opaque
`UUID?`. Neither package imports the other. `TaskDomain` has no knowledge that timers exist.

**Why.** The relationship is genuinely optional in both directions, and the cardinality is
one-task-to-many-sessions. Ownership would force a required relationship in the persistence layer (a
CloudKit relationship — the most fragile construct in SwiftData+CloudKit), and would make "general
timer" a special case of "task timer with a null parent", which is backwards.

**Alternatives.** (a) `Task.activeTimer` — rejected: makes Timer a lifecycle-dependent child, blocks
history, pollutes every task record with timer columns. (b) A `TaskTimerLink` join entity — rejected:
a relationship table for a relationship already expressible as a nullable identifier. (c) One package
with two namespaces — rejected: a namespace is not a boundary; the compiler must enforce this or it
will erode.

```
Task  ←— optional UUID reference —  TimerSession
(TaskDomain)                        (TimerDomain)
        ↖                        ↗
          joined only in AppData
```

## 4. Primary user flows

| # | Flow | Surface |
|---|---|---|
| F1 | Capture an idea into the Pool | all three |
| F2 | Assign a Pool item to Today (with search) | macOS, iOS |
| F3 | Create a task directly into Today | all three |
| F4 | Complete / uncomplete a task | all three |
| F5 | Start a general timer (duration only) | all three |
| F6 | Start a timer *for* a Today task | all three |
| F7 | Pause / resume / stop / reset the active timer | all three |
| F8 | Observe and control a timer started on another device | all three |
| F9 | Review time spent per task (history) | iOS (MVP 2) |

F8 validates the whole architecture and is proven on real hardware in Milestone 4.

## 5. MVP evaluation — the proposed MVP is too large

The proposed MVP is three platforms × two domains × sync × Liquid Glass. Shipping it as one milestone
means the riskiest element (cross-device timer convergence) is validated last, after every UI has been
built on assumptions it might invalidate. Split into three:

**MVP 0 — foundations proven.** TimerDomain + TaskDomain + local SwiftData + CloudKit convergence
proven on disposable two-device shells. No real UI.

**MVP 1 — "it works on my Mac and my iPhone."** macOS menu bar app, iOS app, offline behaviour,
timer presets, expiry notification. This is the first genuinely usable release.

**MVP 2 — "it works everywhere and looks right."** watchOS app, latency hardening, history/per-task
totals (F9), Liquid Glass polish on 26+, layered app icon, accessibility pass.

*What / why / alternatives:* vertical slices over horizontal layers, because a horizontal plan defers
integration risk to the end. One big MVP was rejected because timer-convergence bugs found in month
four would force UI rework across three platforms.

## 6. Recommended Apple technology stack

| Concern | Choice | Why not the alternative |
|---|---|---|
| Language | Swift 6.2, strict concurrency **on from day one** | Retrofitting `Sendable` onto a sync layer costs far more than starting with it |
| UI | SwiftUI + Observation (`@Observable`) | AppKit/UIKit only via interop where SwiftUI lacks the API |
| Persistence | SwiftData | See §13 |
| Sync | SwiftData CloudKit mirroring (private DB) | See §14 |
| Modules | SPM, local packages | No CocoaPods/Carthage; **zero third-party dependencies** |
| Testing | Swift Testing (`@Test`, `#expect`) | XCTest only where tooling requires it (UI tests) |
| Deployment targets | **iOS 18 · macOS 15 · watchOS 11** | Per user decision; Liquid Glass gated to 26+ (§26) |

SwiftData requires iOS 17+/macOS 14+, and `@Observable` requires iOS 17+, so the iOS 18 floor is
comfortably above every framework requirement in this plan. `.tabViewStyle(.sidebarAdaptable)` is
iOS 18, which the floor exactly meets.

Firebase/Supabase/custom backends rejected: single-user private data, CloudKit is free, needs no auth
code, and no backend means no server to operate.

## 7. Package architecture — validated, with one deliberate addition

The proposed four-package structure is **approved**. Adding a fifth; rejecting `SharedCore`.

```
TaskTracker.xcworkspace
├── Packages/
│   ├── TimerDomain     — pure. zero dependencies.
│   ├── TaskDomain      — pure. zero dependencies.
│   ├── AppData         — SwiftData + CloudKit + repository implementations
│   ├── AppFeature      — @Observable controllers + use cases            ← ADDED
│   └── AppDesign       — SwiftUI design system, tokens, adaptive surfaces
├── Apps/  macOS/  iOS/  watchOS/
├── docs/   plans/
├── CLAUDE.md  AGENTS.md  memory.md
```

### Addition: `AppFeature`

**What.** Cross-platform `@Observable` presentation controllers (`ActiveTimerController`,
`TodayController`, `PoolController`) and the use cases they call. Depends on `TaskDomain`,
`TimerDomain`, `AppData`. App targets depend on `AppFeature` + `AppDesign` and contain only views,
scenes, and platform adapters.

**Why.** Without it, "start a timer for task X" — validation, repository call, optimistic local
update, error surfacing — is written three times. *"Do not duplicate Timer business logic across
applications"* binds harder than the anti-fragmentation warning, and this is the only way to satisfy
it. This is an application layer, not a folder.

**Composition roots stay in the app targets.** Three independent executables cannot share one
composition root — different entry points, different platform adapters (menu-bar scene vs.
`WindowGroup` vs. watch scene), different lifecycles. `AppFeature` ships the *ingredients*: controller
types with explicit initialiser dependencies, plus an `AppEnvironment` value bundling the repository
set. Each target constructs its own environment at `@main` and injects it.

**Alternatives.** Controllers in `AppData` — rejected: mixes presentation state with persistence.
In `AppDesign` — rejected: a design system must not own app state. Duplicated per app — rejected
by the rule above.

**Anti-drift rule.** `AppFeature` may contain only `@Observable` types and use cases. Reusable and
stateless → a domain package. Visual → `AppDesign`. Reviewed at every milestone.

### Rejection: `SharedCore`

Not created. The only genuine overlap is a time abstraction (~4 lines) and a couple of error
protocols. Duplicating a four-line protocol is strictly cheaper than a package that couples two
domains §3 exists to separate. **Revisit only if three or more distinct abstractions are duplicated.**

## 8. Dependency graph

```
        TaskDomain          TimerDomain          (pure, no dependencies)
             ↑                   ↑
             └───────┬───────────┘
                  AppData                        (SwiftData, CloudKit)
                     ↑
                 AppFeature                      (@Observable, use cases)
                     ↑
         ┌───────────┼───────────┐
       macOS        iOS       watchOS  ←──── AppDesign (SwiftUI)
```

**Invariants, enforced by package manifests:**
- `TaskDomain` and `TimerDomain` import only the standard library and `Foundation`.
- Neither imports SwiftUI, SwiftData, CloudKit, WatchConnectivity, or the other.
- `AppData` never imports `AppFeature`, `AppDesign`, or any app target.
- `AppDesign` imports SwiftUI only — never a domain, never `AppData`. Components take plain
  parameters, not domain models.
- App targets contain no business rules and no timer arithmetic.

## 9. TaskDomain design

Pure value types, `Sendable`, no persistence vocabulary.

```
TaskDomain/
├── Models/         Task, TaskStatus, DayKey
├── Services/       TaskService (create/edit/complete/schedule rules)
├── Repositories/   TaskRepository (protocol only)
└── Support/        TimeSource, TaskValidationError
```

**`Task`** — `id`, `title`, `notes`, `createdAt`, `completedAt: Date?`, `scheduledDay: DayKey?`,
`updatedAt`. Completion is derived: `isCompleted = completedAt != nil`. One field, not two, so the two
can never disagree after a merge.

**Today assignment: `scheduledDay: DayKey?` on `Task`, not a separate `TaskSchedule` entity.**

*What.* `DayKey` wraps an ISO `yyyy-MM-dd` string, resolved in the device's **current calendar at the
moment of assignment**.

*Why a string key, not a `Date`.* A `Date` meaning "today" is an instant, and an instant is ambiguous
across timezone changes and DST — a task scheduled for the 9th can become the 8th after a flight. A
day key is a *calendar* fact and is stable under both.

*Why not a separate entity.* `TaskSchedule` buys multi-day scheduling and recurrence, both out of
scope. It costs a CloudKit relationship, the most fragile construct in the stack. If recurrence is
ever added, introducing it then is additive: new entity, backfill from `scheduledDay`.

*Alternative.* `isInToday: Bool` — rejected: cannot express "tomorrow", needs a nightly job to clear.

**Pool vs Inbox vs Backlog — we choose "Pool".**

*Why.* An Inbox is a triage queue that must be processed to zero, and a never-emptied Inbox generates
guilt. A Backlog implies prioritised committed work. The described object is neither — it is a durable
reservoir of ideas that is *supposed* to stay full and be drawn from repeatedly. "Pool" is the user's
own word and the only one whose connotation matches the behaviour. `scheduledDay == nil &&
completedAt == nil` **is** the Pool; it is a query, not a container.

**Task invariants.** Title non-empty after trimming; `completedAt` never in the future; completing does
not clear `scheduledDay`; `updatedAt` monotonic per device.

## 10. TimerDomain design

The most important package. Pure, deterministic, no I/O, fully testable without waiting in real time.

```
TimerDomain/
├── Models/       TimerEvent, TimerEventKind, TimerSession, ActiveTimerState, TimerPhase
├── Engine/       TimerProjection (the fold), TimerCalculator (remaining/elapsed)
├── StateMachine/ TimerTransition (validity rules)
├── Policy/       SessionArbitration (deterministic winner selection)
├── Repositories/ TimerEventRepository (protocol only)
└── Support/      TimeSource, LamportClock
```

**`TimeSource`, not `Clock`.** Swift's standard library already defines `Clock`; a domain protocol of
that name is a genuine collision. `protocol TimeSource: Sendable { var now: Date { get } }`.

**The core shape — an append-only log, projected timelessly, then evaluated at an instant.**

```
[TimerEvent] ──project──▶ SessionProjection ──evaluate(at:)──▶ ActiveTimerState ──▶ "42:18"
 (persisted,   (TIMELESS:   (duration,          (time-dependent,    (local, 1 Hz,
  immutable)    log only,    accumulated,        pure, writes         never
                no clock)    runningSince,       nothing)             persisted)
                            terminalEvent?)
```

**These two stages are separated deliberately, and the separation is load-bearing.** An earlier draft
called expiry "derived state" while computing it with `now >= deadline` inside the fold — which
quietly contradicted the log-only invariant two sections earlier. The resolution is not to remove
time, which is impossible, but to put it where it cannot damage convergence:

- **`TimerProjection.project(events) -> SessionProjection` is timeless.** It consults only the log. No
  clock, no device identity, no arrival order. Every device that has seen the same events produces a
  byte-identical projection. This is the invariant §2.7 protects.
- **`TimerCalculator.evaluate(projection, at:) -> ActiveTimerState` is time-dependent and pure.** It
  decides `.running` vs `.completed(.expired)` and computes remaining/elapsed. It is deterministic
  given the same `at`, and **it never writes anything**.

The consequence is precise and worth stating: two devices with skewed clocks may momentarily disagree
about whether a timer has *just* expired. That is not a convergence failure, because nothing is
persisted from an evaluation — the disagreement resolves itself the instant either clock advances
past the deadline, and no divergent state ever enters the log.

`TimerEvent`: `id`, `sessionID`, `kind`, `occurredAt`, `deviceID`, `lamport`, `schemaVersion`, and —
on `.started` only — `duration` and `relatedTaskID`.

`TimerEventKind`: `.started`, `.paused`, `.resumed`, `.stopped`, `.reset`. **There is deliberately no
`.finished` — see §18.**

**Why events rather than a mutable record.** SwiftData's CloudKit mirroring provides **no hook for
custom conflict resolution** and merges at property granularity (§13). A mutable `ActiveTimer` row is
therefore corruptible into states that never existed — one device's `state = .paused` merged with
another's newer `startedAt` yields a paused timer with a running start time, with no API to prevent
it. **Immutable records are never merged.** Two devices writing concurrently produce two rows, not one
torn row, and reconciliation becomes a pure function we own and can exhaustively test.

Secondary benefits, all free: history and per-task totals fall out of the log; offline works by
construction; "what happened" is answerable when debugging.

**Cost, stated honestly.** More types than one mutable row, and the fold must be correct. Mitigations:
it is the most-tested function in the codebase, and the fallback (single record + LWW, accepting torn
state) is a contained retreat that does not change repository protocols.

### Lamport mechanics

`lamport = 1 + max(lamport of every event currently known locally)`, stamped at authoring time and
immutable thereafter. Because devices learn of events only through CloudKit, a Lamport value encodes
exactly *what this device had seen when it authored* — which is the causal information we want, and
nothing more. It is explicitly **not** a measure of recency (§20).

### Determinism requirements on the fold

All directly testable, and all mandatory:

- **Idempotent over duplicates.** CloudKit retries, re-syncs and the WC fast-path (§16) can deliver
  the same logical event twice, and `@Attribute(.unique)` is unavailable under CloudKit sync (§13).
  The fold dedupes by event `id` before folding; folding a multiset equals folding the set.
- **Order-independent.** Events are sorted deterministically before folding, so out-of-order delivery
  cannot change the outcome. Two orderings serve two different questions — see §20.
- **A pure function of the log alone** (projection stage). `project` may not consult the wall clock,
  the local device's identity, or which events arrived first. Any such dependency would let two
  devices compute different projections from identical data, which is the one bug this architecture
  cannot tolerate. Time-dependence lives exclusively in `evaluate(at:)`, which persists nothing.
- **Total.** Every input sequence, including nonsensical ones, produces a valid state. Invalid
  transitions are ignored as stale, never trapped.

### Forward compatibility

`kind` is persisted as a `String`, not an enum raw value, so an unknown kind deserialises rather than
failing. `schemaVersion` accompanies every event. The rule:

- An event with an unrecognised `kind` or a newer `schemaVersion` is **skipped by the projection and
  never deleted from the store.** An older build must not destroy data it does not understand.
- **A session containing any uninterpretable event is quarantined**: rendered read-only with an
  "update required" note, and the device **refuses to author `.paused` or `.resumed` into it**.
  Skipping alone is not enough — a stale client that silently ignored an unknown event could otherwise
  author a `.paused` against a session whose true state it cannot compute.
- **`.started` and `.stopped` remain authorable at all times, including into a quarantined session.**
  This is the deliberate escape hatch, and it is safe for a specific reason: `.stopped` means "this
  session is over" regardless of whether it was running or paused, and `.started` creates a fresh
  `sessionID` entirely — **neither effect depends on the quarantined session's interior state.**
- **`.paused`, `.resumed` and `.reset` are withheld while quarantined.** The first two obviously
  require knowing what the session was doing. `.reset` is withheld for a different and less obvious
  reason: **it discards history, whereas `.stopped` retains it** (§ "Event protocol specifics"). A
  stale client that cannot interpret a session must never be handed the one command that erases it.
  Withholding `.reset` costs the user nothing — `.stopped` already provides a complete escape — while
  permitting it would let an out-of-date device destroy history it does not understand. When in doubt
  between a retaining and a discarding operation, the client that understands less gets the retaining
  one.

**Why the escape hatch cannot be `.started` alone.** Draft 4 claimed a fresh `.started` "always
supersedes", so a user could never be locked out. That is false, and the counter-example is exactly
the pathology this section exists to survive: if the quarantined winning session carries a
**future-skewed `startedAt`** — authored by a device whose clock was months ahead — then a genuinely
fresh start authored today sorts *behind* it under `(occurredAt, deviceID)` and is superseded the
instant it is created. The user would be permanently stuck looking at a timer they cannot pause,
cannot stop, and cannot replace. Allowing `.stopped` fixes this completely and deterministically:
every device sees the `.stopped`, the skewed session becomes terminal, and the state becomes
**`.idle`**.

**Always `.idle` — never a "next-greatest" session.** An earlier phrasing of this paragraph said the
next-greatest session takes over, which contradicts §20 and the worked example there. Supersession is
irreversible: every session below the maximum was permanently terminated at the instant it was
displaced, and terminating the maximum does not revive any of them. §20 is canonical. Stopping the
active timer — quarantined, skewed, or ordinary — always yields `.idle`, and the user starts fresh
from there.

**The general invariant this establishes: the user can always stop whatever timer is active.** No
combination of clock skew, version skew or partition can produce a timer that cannot be terminated.
This is stated as a product guarantee, not merely an implementation detail, and it is a required test
(§27).

**Quarantine is recomputed, never stored.** It is a predicate over the session's events — *does any
event here have an unknown `kind` or a `schemaVersion` above mine?* — evaluated on every projection.
When the device updates to a build that understands the kind, the predicate goes false and quarantine
lifts automatically. There is no quarantine flag to persist, sync, or migrate, and therefore no way
for a stale quarantine marker to outlive its cause.

### Arbitration must never depend on interpreting unknown kinds

Quarantine is scoped per session, which leaves a hole worth closing explicitly: if a future schema
introduced a *new way to begin a session*, an old client would not recognise it, would omit it from
arbitration, and would keep authoring into a session that had in fact already been displaced —
breaking the no-resurrection guarantee of §20 from the outside.

The rule that closes it: **`.started` is a reserved, permanently stable kind. Schema evolution may add
new event kinds, but may never add a second way to begin a session.** Session genesis is
`kind == "started"`, forever. Combined with additive-only fields — `id`, `sessionID`, `kind`,
`occurredAt`, `deviceID`, `lamport`, `schemaVersion` are present on every event in every future
version — this guarantees that **arbitration (§20) reads only v1 fields and is fully computable by
any client, of any age, without interpreting a single unknown kind.** An old client may not know what
happened *inside* a newer session, but it always knows that the session exists and when it started,
which is all arbitration requires.

This matters because three devices will not update simultaneously.

### Event protocol specifics

- `.reset` returns to `.idle` and terminates the session **without retaining elapsed time in
  history** — it means "that didn't happen". `.stopped` means "I finished early" and **is** retained.
  This distinction is the entire reason both exist.
- `.started` is the only event carrying `duration` and `relatedTaskID`; both immutable for the
  session's lifetime.
- The store is append-only. Events are never mutated or deleted by normal operation (§28).

## 11. Task ↔ Timer association strategy

`TimerEvent.relatedTaskID: UUID?`, set once on `.started`, immutable thereafter.

*Why immutable.* A session records what you were doing at the time; re-pointing it later would rewrite
history and corrupt per-task totals.

*Why `UUID?` and not a typed reference.* A typed reference requires `TimerDomain` to import
`TaskDomain` (§3). A `UUID` is a primitive both sides understand.

*Referential integrity.* Deliberately **not** enforced. A deleted task leaves sessions with a dangling
ID; the join in `AppData` resolves it to "Deleted task" for display. Enforcing it would require a real
relationship, which §3 and §13 rule out.

*Alternative.* A `TaskReference` protocol that `TaskDomain.Task` conforms to — rejected: inverts the
dependency and achieves nothing a `UUID` does not.

## 12. TimerSession vs ActiveTimerState — both, and both derived

**Decision: keep the distinction, and make both computed rather than separately stored.**

| | `TimerSession` | `ActiveTimerState` |
|---|---|---|
| Represents | one focus run, past or present | the single logically-active timer, globally |
| Cardinality | many | exactly zero or one |
| Lifetime | permanent (history) | momentary |
| Source | projection of one session's events, plus its supersession boundary | arbitration → projection → evaluation (§10, §20) |

**The canonical type**, which earlier drafts stated inconsistently across §10, §12 and §18:

```swift
enum ActiveTimerState {
    case idle
    case active(TimerSession, TimerPhase)         // TimerPhase: .running(since: Date) | .paused
    case completed(TimerSession, CompletionReason) // .expired | .stoppedEarly | .superseded
}
```

The `.completed` case is required and was missing from Draft 4's definition while §10 and §18 both
produced it — a genuine contradiction, not a wording slip. `.completed` is what `evaluate(at:)`
returns when the winning session has passed its deadline (`.expired`) or carries a terminal event
(`.stoppedEarly`), and what a superseded session evaluates to in history (`.superseded`). The UI shows
`.completed(.expired)` as a finished timer awaiting acknowledgement; `.idle` means there is nothing to
show at all. Collapsing the two would lose the "your timer finished" moment entirely.

**Storage: only `TimerEvent` is stored, and it is the only thing synchronised. No session snapshots.**

An earlier draft materialised a `TimerSessionRecord` on session termination. That was a mistake and is
removed. A *synchronised* snapshot is a mutable record two devices can both author for the same
session — handing CloudKit exactly the merge decision §14 exists to avoid, and reintroducing torn
state in the one place nobody would look for it.

History is computed by folding the log, which is cheap at this volume (§28). If profiling ever
justifies a materialised cache, it must be **local-only and never synchronised** — derived state stays
on the device that derived it. The synced schema therefore contains exactly two entities:
`TaskRecord` and `TimerEventRecord`.

*Alternative.* Store both as independent mutable records — rejected: two writable representations of
one fact, guaranteed to disagree after a merge.

## 13. Persistence technology comparison

| | SwiftData + CloudKit | Core Data + NSPersistentCloudKitContainer | Raw CloudKit / CKSyncEngine | Hybrid |
|---|---|---|---|---|
| Cross-platform | ✅ | ✅ | ✅ | ✅ |
| Clean inside SPM packages | ✅ | ⚠️ `.xcdatamodeld` in packages is awkward | ✅ | ⚠️ |
| Swift 6 concurrency fit | ✅ `@ModelActor` | ⚠️ `NSManagedObject` is not `Sendable` | ✅ plain values | ⚠️ |
| Offline | ✅ automatic | ✅ automatic | ❌ you build the queue | ⚠️ |
| Custom conflict resolution | ❌ **none** | ⚠️ merge policies only | ✅ full control | ✅ |
| `@Attribute(.unique)` | ❌ unsupported with sync | ❌ | n/a | ❌ |
| Relationships under sync | ⚠️ fragile | ⚠️ fragile | manual | ⚠️ |
| Implementation cost | low | medium | **high** | high |

**The decisive constraint:** SwiftData+CloudKit requires every property to be optional or defaulted,
forbids unique constraints, syncs only the private database, and **exposes no custom merge hook**.
This is the contract, not a bug to work around.

## 14. Final persistence recommendation

**SwiftData + CloudKit private-database mirroring, for everything — with an append-only event log for
timer state so the missing merge hook stops mattering.**

*What.* One synced `ModelContainer`,
`cloudKitDatabase: .private("iCloud.com.diwan.TaskTracker")`, holding exactly **`TaskRecord` and
`TimerEventRecord`**. All properties optional or defaulted, no unique attributes, **no CloudKit
relationships anywhere** — associations are `UUID` fields resolved in `AppData`. A **second,
non-synced** container holds only the WC staging store (§16).

*Why.* Offline, background sync, watchOS support and migrations for near-zero code, and its one
disqualifying weakness is neutralised by never asking it to merge anything: task edits are
low-conflict and property-level LWW is genuinely fine for them; timer state is high-conflict and is
expressed as immutable events that are appended, never updated.

*Alternatives.* **Core Data + CloudKit** — same sync engine, worse Swift 6 ergonomics, model file
fits poorly in SPM; its merge policies are still property-level and would not save us. **CKSyncEngine
/ raw CloudKit** — full control, but we hand-build the local store, offline queue, change-token
bookkeeping and watch path: months of infrastructure to buy what the event log already provides.
**Hybrid (SwiftData for tasks, CKSyncEngine for the timer)** — the honest second choice; rejected
because it means two sync engines, two failure modes, two offline queues and two debugging stories to
solve a problem immutability already solves. **NSUbiquitousKeyValueStore** — latest-wins is precisely
the torn-state problem we are avoiding, and it keeps no history.

## 15. Local-first architecture

```
User action → AppFeature controller → repository (AppData)
           → SwiftData write (local, immediate)
           → UI updates from local store
           ⋮
           → CloudKit mirroring uploads when able (background, invisible)
```

No user-facing operation ever awaits the network. The UI reads only the local store. Sync status is
ambient information, never a blocker or a modal. Offline is the normal case, not an error. Everything
in the offline requirement list — create, edit, complete, schedule, start, pause, resume, stop — is a
local write plus, for timers, a local append.

## 16. CloudKit synchronisation architecture

- One private container, one zone, single user, no sharing.
- Schema pushed from development and promoted to production before any release.
- `AppData` owns all CloudKit contact. `AppFeature` and app targets never import CloudKit.
- A `SyncStatusMonitor` publishes ambient state (`.synced`, `.syncing`, `.offline`,
  `.accountUnavailable`).
- **iCloud disabled / signed out:** fully functional against the local store; says so once, plainly;
  does not nag or block.
- **Account change:** SwiftData tears down and rebuilds the store. Treated as a fresh device.

**`TimerEventTransport` seam.** `AppData` defines a `TimerEventTransport` protocol with a CloudKit
implementation. If the §24 spike shows CloudKit alone cannot carry the watch experience, a
WatchConnectivity fast-path is an *additional* implementation, not a re-architecture.

### Dual-ingress design — storage semantics, not just a dedupe assertion

If a WC path is added, the same logical event arrives twice: over WC in milliseconds, over CloudKit
minutes later. Skipping the duplicate at fold time is **not sufficient** — if a WC-received event were
inserted into the *synced* store, SwiftData would mirror it to CloudKit from the receiving device too,
producing genuinely duplicated persistence and a second authoring device for one user action.

The design:

1. **Only the authoring device ever writes an event to the synced store.** This is the invariant.
2. WC-received events are inserted into a **separate, non-mirrored local staging container** (§14),
   preserving the original `id`, `deviceID`, `occurredAt`, `lamport` — never re-stamped.
3. The fold reads `union(syncedStore, stagingStore)` and dedupes by `id`. The staging copy is a
   *faster view of the same fact*, not a second fact.
4. When the canonical row arrives via CloudKit, the staging copy is redundant and is pruned locally.
   Pruning the staging store is safe precisely because it is never a source of truth.
5. **WC is never a correctness dependency.** An app that ignores every WC message must converge to the
   identical state. This is the invariant the fake-transport tests (§27) assert.

## 17. Timer synchronisation strategy

**Synchronised:** immutable `TimerEvent` rows — five kinds, a handful per session.
**Never synchronised:** remaining time, elapsed time, or any per-second value.

A 60-minute session with two pauses produces **five records for the entire hour**, versus 3,600 writes
if remaining seconds were mirrored.

```
START:  { kind: .started, occurredAt: 14:00:00Z, duration: 3600, sessionID: S1, lamport: 1 }
PAUSE:  { kind: .paused,  occurredAt: 14:18:30Z, sessionID: S1, lamport: 2 }
RESUME: { kind: .resumed, occurredAt: 14:25:00Z, sessionID: S1, lamport: 3 }
```

Every device projects these once, then re-runs `evaluate(at:)` locally at 1 Hz via `TimelineView` —
the projection is recomputed only when the log changes, while the countdown re-evaluates each tick.
The display refresh touches no persistence whatsoever.

*Why not sync a countdown.* Thousands of CloudKit writes per session, rate limits, battery drain — and
still wrong, because a received "remaining" value is already stale. Timestamps do not go stale.

## 18. Timer state machine

```
                ┌──────── reset ─────────┐
                ▼                        │
            ┌───────┐   start      ┌───────────┐
   ────────▶│ idle  │─────────────▶│  running  │
            └───────┘              └───────────┘
                ▲                    │       ▲
        stop /  │             pause  │       │ resume
   (expiry)     │                    ▼       │
                │                ┌───────────┐
                └────────────────│  paused   │
                       stop      └───────────┘
```

| From | start | pause | resume | stop | reset |
|---|---|---|---|---|---|
| idle | → running | – | – | – | – |
| running | new session (§20) | → paused | – | → completed(.stoppedEarly) | → idle (discarded) |
| paused | new session (§20) | – | → running | → completed(.stoppedEarly) | → idle (discarded) |
| completed | → running (new session) | – | – | – | → idle |

**Expiration is derived, never an event.** There is deliberately no `.finished` kind.

*Why this matters.* A 60-minute timer expiring at 15:00 while all three devices are asleep has **no
author**. If completion were an event, every device would race to write one on wake, producing
duplicates and disagreement about a fact that is nobody's decision. Instead:

```
phase == .running && now >= startedAt + duration + accumulatedPaused  ⟹  .completed(.expired)
```

Any device computes this **identically for the same `at`**, including after a week of downtime, with
no process having been alive. (Not "identically at any time" — §10 is explicit that two devices with
skewed clocks may momentarily disagree about a *just*-expired timer. That is harmless precisely
because evaluation persists nothing.) This is the direct implementation of *"do not rely on a running process to preserve
timer truth."* Only `.stopped` and `.reset` are user-authored terminal events.

**Invalid and stale transitions are ignored, not errors.** A `.resumed` arriving for an
already-stopped session is a device that was behind; the fold drops it. `TimerTransition` returns `nil`
for invalid input. Nothing throws; nothing crashes.

## 19. Timer calculation strategy

All arithmetic lives in `TimerCalculator` — pure functions of `(session, at: Date)`, no stored mutable
state, no `Timer`, no `Task.sleep`:

```
elapsed(at:)   = accumulatedActive + (phase == .running ? at - runningSince : 0)
remaining(at:) = max(0, duration - elapsed(at:))
```

`at` is always injected, never `Date()` inside the function — this is what makes a three-hour scenario
a sub-millisecond test. Nothing accumulates frame-by-frame, so there is no drift. The view re-derives
from timestamps every tick; a missed tick is invisible.

**Clock concerns.** Instants are UTC, so timezone changes and DST are non-events by construction. A
user manually setting the device clock backwards *will* distort a running timer — accepted and
documented; see §20 for why this is handled at authoring time rather than in the fold.

## 20. Conflict resolution strategy

**The honest answer first: a single globally-active timer cannot be *enforced* across partitioned
devices without a central authority.** CloudKit provides no distributed lock. Two offline devices can
each legitimately believe they started a timer. What we guarantee is that when they meet, every device
reaches the *same* answer, deterministically, and that nothing is lost.

### Two orderings, because there are two different questions

| Question | Ordering | Why |
|---|---|---|
| Within one session, what order did its events occur in? | `(lamport, occurredAt, deviceID)` | These events are usually **causally related** — a resume authored by a device that had already seen the pause. Lamport captures exactly that, and correctly beats a skewed wall clock. |
| Between sessions, which is active? | `(startedAt, deviceID)` — **wall clock** | Two offline devices that never saw each other's events are **causally concurrent**. Their Lamport counters were incremented independently and bear no relationship to one another; comparing them answers nothing. |

**Lamport clocks encode causality, not chronology.** A busy device has a high counter purely because
it has seen many events. Using that to decide which of two independent starts is "more recent" would
let an active device beat a device that genuinely started later — a bug, not a policy.

### Arbitration rule — total, permanent, and purely a function of the log

Order every `.started` event by `(startedAt, deviceID)`. Then:

- **The greatest one is the only session that may be active.**
- **Every earlier session is permanently terminated as `.superseded`, at the instant the next session
  started** — regardless of whether that later session is itself still running, stopped, reset or
  expired.

Supersession is therefore **monotone and irreversible**. This is deliberate, and it fixes a real defect
in an earlier draft: a rule phrased as "arbitrate when more than one session is currently
non-terminal" would let a superseded session *resurrect* the moment the winner was stopped, resurfacing
a timer the user had already replaced hours earlier. Once displaced, always displaced.

**`deviceID` is a final tiebreak** purely to make the ordering total, so all devices agree even on
identical timestamps.

**No receiver-relative filtering.** An earlier draft proposed excluding events whose `startedAt` looked
implausible "relative to the receiving device". That is forbidden by §2.7 and §10: two devices with
different clocks would exclude different events and compute different winners from the identical log —
silently breaking convergence, the one property the whole design rests on. Clock skew is therefore
handled **at authoring time only**: a device whose clock is grossly wrong is a local problem, detected
against CloudKit's server timestamp and surfaced as a one-line advisory to the user. The fold never
filters.

**The loser becomes history, not a deletion.** A superseded session is retained in the log with its
real elapsed time and task link, and appears in history as superseded. This is what *"resistant to
silent data loss"* requires: the work is preserved; only its claim to be *active* is revoked.

**Why last-start-wins.** It matches intent: the most recent explicit "start" is the user's current
intention. First-start-wins would resurrect a forgotten timer over a deliberate new one.

**Alternatives.** *Server modification time* — rejected: reflects upload order, not user action order,
so a late-syncing device wins spuriously. *Optimistic locking on a mutable record* — rejected: needs a
compare-and-swap SwiftData does not offer. *User-facing conflict prompt* — rejected for MVP: a modal
about merge semantics on wake is worse than a deterministic answer plus inspectable history. *CRDT* —
rejected: an append-only log with a total order already is one, for this shape of data.

**Worked example.** Mac, offline, starts session A at 14:00 (Lamport 5 — that Mac has seen a lot of
history). iPhone, offline, starts session B at 14:10 (Lamport 3). Both reconnect at 14:20. Every device
arbitrates on `startedAt`: **B is active**, running since 14:10. A is permanently terminated as
`.superseded` at 14:10 and retained with its real 10 minutes. If the user now stops B, the state is
`.idle` — A does **not** come back. Mac, iPhone and Watch all show the same thing.

A's higher Lamport counter is correctly ignored: it reflects only that the Mac had processed more
events, which says nothing about when the user pressed start.

## 21. macOS architecture

`MenuBarExtra(.window)` as the primary and, in MVP 1, only surface.

- **Menu bar label:** an SF Symbol when idle; when active, a monospaced-digit countdown (`42:18`),
  optionally prefixed with a task title truncated to ~18 characters. Rendered by a `TimelineView` that
  calls `evaluate(at:)` on the cached projection each tick — no `Timer`, no arithmetic in the view.
- **Panel:** Today list with single-click completion, active timer with controls, a quick-add field
  focused on open, Pool search behind one keystroke.
- **Preferences** for label verbosity (icon only / timer / timer + task) via a `Settings` scene.
- A conventional window for Pool management and history arrives in MVP 2 via `WindowGroup`; the menu
  bar remains primary.
- `LSUIElement` accessory activation policy so no Dock icon appears.

*Why `MenuBarExtra(.window)` over `.menu`.* `.menu` cannot host a text field, a live-updating
countdown, or a list with per-row controls. *Why not `NSStatusItem` directly?* `MenuBarExtra` covers
the requirement; AppKit interop remains available (R-7).

## 22. iOS architecture

`TabView` with `.tabViewStyle(.sidebarAdaptable)` (iOS 18 — exactly our floor) so iPhone gets tabs and
iPad gets a sidebar for free.

Tabs: **Today** · **Pool** · **Timer** · **Settings**.

*Evaluation of the proposed IA.* Right, with one refinement: Timer as a peer tab is correct *because*
timers are independent of tasks — demoting it to a Today detail would contradict §3. Today and Pool are
separate tabs rather than one segmented list because they are different mental modes (commitment vs.
capture), and merging them is what makes task apps feel heavy.

`NavigationStack` with a typed path per tab. Task editing is a sheet. Pool→Today is a swipe action,
matched by an identical context-menu action.

## 23. watchOS architecture

Standalone watchOS app (`WKRunsIndependentlyOfCompanionApp`), embedded in the iOS app for a single App
Store record but functional without the phone.

Two screens, no deeper hierarchy: **Active Timer** (large monospaced countdown, one primary control,
secondary controls behind a swipe) and **Today** (tap to complete, long-press to start a timer). A
two-page `TabView`.

MVP 2 only. Explicitly deferred: complications, Smart Stack widgets, watch-face integration, haptic
expiry alerts, background refresh tuning.

*Why standalone.* The timer is shared state in iCloud and the watch can reach iCloud on its own.
Requiring the phone would make the watch a worse client for no architectural gain.

## 24. WatchConnectivity vs CloudKit

**Decision: CloudKit is the primary and, in MVP, the only path. WatchConnectivity is deferred behind a
measurement.**

*Why.* Apple's guidance is explicit that WatchConnectivity must be *"an opportunistic optimization,
rather than the primary means of supplying fresh data"* — users may never install the companion, and a
paired reachable phone is not guaranteed. Building on it as primary means building a second full sync
path with different failure modes.

*Alternatives.* *WC-primary* — rejected per the above. *Hybrid from day one* — rejected as premature:
two transports and two debugging stories before knowing whether one suffices.

**The open question, stated as a risk rather than assumed away.** CloudKit push latency to a sleeping
watch may not meet the promise implied by *"I tap Pause on the Watch and the Mac reflects it."*
Milestone 0 spike R-1 measures it. If the numbers are poor, the `TimerEventTransport` seam plus the
dual-ingress design (§16) accepts a `sendMessage` fast-path as a strictly additive change. This
decision is made with data in Milestone 7, not speculation now.

## 25. Swift concurrency strategy

Swift 6 language mode, strict concurrency, from the first commit.

| Layer | Model |
|---|---|
| `TaskDomain`, `TimerDomain` | Pure `Sendable` value types and free functions. **No actors, no async** — the fold is synchronous and deterministic; making it async would buy nothing and cost testability. |
| `AppData` | `@ModelActor` for background SwiftData work; repositories actor-isolated; boundaries exchange `Sendable` value types, never `PersistentModel` instances. |
| `AppFeature` | `@MainActor @Observable` controllers; `async` methods awaiting repositories. |
| App targets | `@MainActor` throughout. |

Hard rule: **SwiftData model objects never cross an isolation boundary.** Repositories map records to
domain value types at the edge, both directions. This is the single most effective defence against the
class of Swift 6 errors that make SwiftData painful, and it keeps the domains persistence-ignorant —
one rule, two benefits.

## 26. AppDesign / Liquid Glass strategy

**The floor is iOS 18 / macOS 15 / watchOS 11, so Liquid Glass is conditional, not assumed.** Every
Liquid Glass API (`.glassEffect`, `.scrollEdgeEffectStyle`, `.tabBarMinimizeBehavior`,
`.backgroundExtensionEffect`, `GlassEffectContainer`) is 26+ and must be availability-gated.

**The mechanism: one call site, two implementations — at component level, not just modifier level.**

`AppDesign` exposes semantic surfaces and resolves them internally:

```
if #available(iOS 26, macOS 26, watchOS 26, *)  →  .glassEffect(...)
else                                            →  .background(.regularMaterial)
```

Feature code never writes `#available` and never names a material. But **modifiers alone are not a
sufficient seam**, because Liquid Glass differs *structurally*, not only visually: `GlassEffectContainer`
groups sibling glass elements and morphs between them, toolbars gain grouping and spacer semantics,
and tab bars gain minimise-on-scroll. None of that is expressible as "swap one background for another."

The seam is therefore **component-shaped**, and `AppDesign` exports availability-gated
`@ViewBuilder` containers and components alongside the modifiers:

| Seam | 26+ | Floor (iOS 18 / macOS 15 / watchOS 11) |
|---|---|---|
| `.navigationSurface()` | `.glassEffect()` | `.background(.regularMaterial)` |
| `.floatingControlSurface()` | `.glassEffect(in:)` + `.interactive()` | material + subtle shadow |
| `SurfaceGroup { }` | `GlassEffectContainer { }` | passthrough container |
| `AppToolbar { }` | grouped items + `ToolbarSpacer` | conventional `ToolbarItemGroup` |
| `AppTabView { }` | `.tabBarMinimizeBehavior(.onScrollDown)` | plain `TabView` |
| `.contentScrollEdge()` | `.scrollEdgeEffectStyle(.hard, for: .top)` | no-op |

This confines the entire dual-appearance problem to one package, keeps the branching out of every
feature, and makes deleting the fallback when the floor eventually rises a single-package change.
**Both paths are laid out and reviewed, not just the modern one** — the floor build is what most of
the user's devices may actually run, so it is a first-class appearance, not a degraded mode.

**Rules (applying to the 26+ path):**
- Glass belongs to the **navigation layer** only. Task rows and list content get **no glass** — glass
  on the content layer competes with navigation and reads as noise.
- Regular variant everywhere. The Clear variant requires media-rich content, an acceptable dimming
  layer, and bold bright foreground content; this app satisfies none of the three, so Clear is banned
  outright rather than left to taste.
- No custom backgrounds on toolbars or navigation; no `.presentationBackground` on sheets; no
  `UIVisualEffectView`/`NSVisualEffectView`; no hard-coded row heights or control frames.
- `.tint()` reserved for the single primary action in a context — the timer's primary control.
- Adjacent glass controls go inside a `GlassEffectContainer`; default stack spacing, never tightened.

**`AppDesign` contents:** tokens (spacing, radii, durations), typography (semantic text styles only,
full Dynamic Type), `AppSymbols` (one SF Symbols catalogue so three apps cannot drift), and the
adaptive surface modifiers above, plus `TimerDisplay` (monospaced-digit, size-adaptive),
`TimerControlCluster`, `TaskRowContent`, `EmptyStateView`. Components take plain values, never domain
models.

**Platform divergence is intentional.** macOS is dense and keyboard-first; iOS is touch-first and
navigational; watchOS prioritises glanceability with **minimal transparency and high contrast** — the
watch is viewed at arm's length in sunlight, so it takes the tokens and the symbol catalogue but very
little of the glass.

**Accessibility is not a later pass.** Dynamic Type at all sizes, VoiceOver labels on every icon-only
control, verification under Reduce Transparency, Increase Contrast and Reduce Motion — which Liquid
Glass honours automatically on 26+, provided we have not overridden it, and which the material
fallback must also respect on the 18/15/11 path.

**App icon** built in Icon Composer as three layers, all appearance variants reviewed, circular watchOS
mask checked. Layered icons apply on 26+; a conventional icon ships for the older floor.

## 27. Testing architecture

Swift Testing throughout. **The domain packages hold the test mass**, because they hold all the risk
and none of the I/O.

- **TimerDomain (highest density).** Every valid and invalid transition; remaining/elapsed across
  pause/resume cycles; expiry evaluation including "expired while all devices asleep"; projection
  **idempotence over duplicated events**; projection **order-independence** (property test: shuffle
  the log, assert identical projection); **projection timelessness** (projecting the same log under
  two wildly different `TimeSource`s must give byte-identical results — this is the test that guards
  §2.7); **bounded-query equivalence** (randomised logs, bounded path vs. full-log reference fold,
  §28); **arbitration permanence** (stopping the winner must not resurrect a superseded session);
  two-offline-starts; stale-command rejection; **supersession cutoff** (a session displaced at 14:10
  contributes exactly its truncated elapsed time to per-task totals, never an open-ended interval);
  **the "always stoppable" guarantee** (a future-skewed, quarantined, or otherwise pathological winner
  can always be terminated by `.stopped`, and the user is never locked out); quarantine behaviour on
  unknown event kinds, including that it lifts once the kind becomes known and that
  `.started`/`.stopped` remain authorable while quarantined but `.reset` does not; and that stopping
  the active session always yields `.idle` rather than reviving a superseded one. Randomised property
  tests cover
  duplicates, timestamp ties on `deviceID`, and mixed-version logs. All via an injected `TimeSource` —
  **no test ever waits in real time**.
- **TaskDomain.** Creation validation, completion idempotence, Pool↔Today transitions, `DayKey`
  behaviour across a timezone change and a DST boundary.
- **AppData.** In-memory `ModelContainer` round-trips, mapping fidelity, migration from a fixture
  store, staging-store pruning, and repository conformance run against the same suite as the fakes.
- **Sync.** A `FakeTimerEventTransport` simulating delay, reordering, duplication and partition,
  driving two simulated devices to assert convergence — including the invariant that ignoring every WC
  message yields identical state. This proves F8 without hardware.
- **Platform.** Light. Menu-bar label rendering, `scenePhase` restoration, watch lifecycle. Manual
  cross-device verification for the real F8 walkthrough.

**Pre-completion checklist (every task):** builds for all three platforms with zero warnings under
strict concurrency; domain tests pass; no timer arithmetic outside `TimerDomain`; no persistence type
in a domain package; docs and `memory.md` updated in the same session.

## 28. Important edge cases

**Must be solved for MVP:**

| Case | Resolution |
|---|---|
| Task completed on two devices | Idempotent; LWW on `completedAt` is harmless — both agree it is done |
| Task edited on two devices | Property-level LWW; acceptable for single-user title/notes edits |
| Task moved to Today offline | Local write, syncs later; `DayKey` is calendar-stable |
| Timer started on two devices | §20 — latest `(startedAt, deviceID)` wins; loser permanently superseded and retained |
| Winner later stopped | State is `.idle`; superseded sessions never resurrect (§20) |
| Simultaneous pause | Both append `.paused`; fold is idempotent; identical result |
| Stop here, Resume there | Intra-session Lamport order decides; a `.resumed` after `.stopped` is dropped as stale |
| Stale device sends old state | Lower Lamport within the session; ignored |
| **Timer expires while all apps suspended** | Computed by the next `evaluate(at:)` (§18) — no process needed |
| Mac sleeps for hours | Re-derives from timestamps on wake; no drift |
| iPhone terminated / relaunched | State is in the store, not in memory |
| Long offline period then reconnect | Batch folds to one deterministic state |
| Out-of-order CloudKit delivery | Fold sorts before folding |
| Duplicate records | Dedupe by event `id` — mandatory, since unique constraints are unavailable |
| Event from a newer app version | Skipped, never deleted; session quarantined read-only (§10) |
| iCloud disabled / signed out | Fully functional locally; stated once, plainly |
| Timezone change / DST | Instants are UTC; `DayKey` is a calendar fact — both are non-events |

**Bounded queries — and why they provably equal the full-log fold.**

Folding never scans the whole log. An earlier draft proposed filtering on `occurredAt >=
greatestStart`, which is **wrong**: a device with a skewed clock can author a `.paused` whose
`occurredAt` precedes its own session's start, and that filter would silently drop it. The correct
decomposition is by session identity, not by time:

- **Q1 — the session-start index.** Fetch `kind == "started"`, sorted by `(occurredAt` ascending`,
  deviceID` ascending`)`. Backed by `#Index` on `(kind, occurredAt, deviceID)`. This yields a small,
  totally-ordered list of `(sessionID, startedAt, deviceID)` — one entry per session ever started.
  **The last entry is the active session** (the §20 maximum). For a `.started` event `occurredAt` *is*
  its `startedAt`, so no separate field is needed.
- **Q2 — projection.** Fetch `sessionID == <target>` — every event of that session, unfiltered by
  time. A handful of rows. Backed by `#Index` on `sessionID`.
- Project Q2 **with its supersession boundary from Q1** (below), then evaluate at now.

Both queries read the **union of the synced store and the WC staging store** (§16), deduped by event
`id`, exactly as the reference fold does.

### A session's projection needs one fact from outside itself

Draft 4 claimed a session's projection "depends only on events carrying its own `sessionID`". That is
false for any session that was superseded, and the error would have surfaced as quietly wrong per-task
totals: **a superseded session's elapsed time is cut off at the instant its successor started, and
that instant lives in the successor's `.started` event.** Nothing inside the superseded session
records that it ended.

The correction: projection takes an explicit boundary.

```
project(events, supersededAt: Date?) -> SessionProjection
```

`supersededAt` comes from the Q1 index and nowhere else: **for the session at index *i*, it is the
`startedAt` of the session at index *i+1*; for the last entry it is `nil`.** The index is already
totally ordered by `(startedAt, deviceID)`, so this is a single lookup, and it is a pure function of
the log — no clock, no device identity. The active session always has `supersededAt == nil`, which is
why the current-state path never noticed the omission.

History and per-task totals (F9) therefore project each session **with its boundary**, never in
isolation. A session that ran 14:00–14:10 before being displaced contributes exactly ten minutes, not
the open-ended interval its own events would suggest.

**Equivalence argument.** The full-log fold picks the active session as the maximum over all
`.started` events by `(occurredAt, deviceID)` — precisely the last entry of Q1. A session's projection
depends only on its own events *plus* its `supersededAt` boundary, both of which Q1+Q2 supply.
Supersession is terminal and irreversible (§20), so no superseded session can affect the active state.
Therefore the bounded path and the reference fold agree.

**This is asserted as a tested property, not a claim.** `TimerDomain` ships a reference
implementation that folds the entire log, and a randomised test generates logs — including skewed
timestamps, duplicates, out-of-order delivery and multiple competing sessions — asserting that the
bounded path and the reference fold produce identical state. If the optimisation ever diverges from
the definition, that test fails.

History is paginated per session with `fetchLimit`. Per-task totals (F9, MVP 2) query `.started`
events by `relatedTaskID` to obtain session IDs, then project each; if that ever profiles slow, the
cache is local-only and never synced (§12).

**Deferred with a stated position:** app reinstall (accepted — CloudKit repopulates; no local backup
in MVP); iCloud account switch (store rebuild, treated as a new device); manual clock change (detected
at authoring, advisory only — never filtered in the fold, §20).

**Compaction is out of MVP entirely, and deliberately not half-designed.** A focus timer emits ~10
events/day; a decade is well under 40,000 small rows, which the bounded queries above handle
comfortably. Deleting records from an append-only log that is mirrored to CloudKit and read by
devices that may be offline for weeks is a genuine data-loss hazard — a device that has not seen a
deletion will happily re-upload the row it still holds. Any compaction scheme therefore needs a real
tombstone protocol, and that gets **its own ADR and its own milestone, after MVP 2**. No code, no
partial design, no deletions in MVP.

**One local notification is in scope** *(confirmed by the user)*. A timer expiring while backgrounded
must tell the user, or the product does not work. Scheduled locally at `.started` with the computed
fire date, cancelled on pause/stop/reset, rescheduled on resume — purely local, no push. Three devices
would otherwise fire three alerts, so a per-device "notify on this device" preference ships with it,
defaulting on for macOS and off elsewhere.

## 29. Technical risks

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R-1 | **CloudKit propagation latency to watchOS may not meet the product promise** | **High** | Spike in Milestone 0; `TimerEventTransport` + dual-ingress design make the WC fast-path additive (§16, §24) |
| R-2 | SwiftData+CloudKit schema mistakes are expensive to undo once records exist | **High** | Freeze schema in Milestone 0; two entities only; every property optional-or-defaulted; zero relationships; zero unique attributes; migration test before any release |
| R-3 | The fold is the single point of correctness for the entire timer feature | Medium | Highest test density in the codebase; property-based order/duplicate/permanence tests; pure and I/O-free by construction |
| R-4 | Event-sourcing complexity exceeds its payoff | Medium | Reassess after Milestone 4 against a defined fallback (mutable record + LWW) that does not change repository protocols |
| R-5 | Swift 6 strict concurrency friction with SwiftData | Medium | Domain values never cross boundaries as models; `@ModelActor`; strict mode from commit one |
| R-6 | **Dual-appearance cost: every surface must work with and without Liquid Glass, on all three platforms** | **Medium** | Confined to the component-level compatibility seam in `AppDesign` (§26) — modifiers *and* `@ViewBuilder` containers, since Liquid Glass differs structurally, not just visually; feature code never branches; both appearances laid out, reviewed, and verified under accessibility settings |
| R-7 | `MenuBarExtra(.window)` has known rough edges for focus and dismissal | Low | Prototype in Milestone 5 before committing the macOS UX; AppKit interop as fallback |
| R-8 | CloudKit development→production schema promotion is one-way | Medium | Promote deliberately in Milestone 4 with a written checklist; never ship against development |
| R-9 | Staleness across non-simultaneous device updates | Low | `schemaVersion`, skip-don't-delete, and session quarantine (§10) |

## 30. Documentation strategy

```
CLAUDE.md    → how Claude works in this repo (concise, links out, never duplicates docs/)
AGENTS.md    → rules for any coding agent; boundaries, prohibitions, completion checklist
memory.md    → what is true right now (state, active work, next steps)
docs/        → durable design and the reasoning behind it
```

> **memory.md says what is happening now. docs/ says how the system is designed and why.**

| File | Owns |
|---|---|
| `PRODUCT.md` | Vision, user, terminology (Pool/Today/Session), workflows, MVP tiers, out-of-scope |
| `ARCHITECTURE.md` | Packages, targets, dependency graph, layers, data flow, concurrency boundaries |
| `TASK_ARCHITECTURE.md` | TaskDomain model, `DayKey`, Today/Pool semantics, lifecycle, invariants |
| `TIMER_ARCHITECTURE.md` | **The most important document.** Event log, Lamport mechanics, fold, state machine, derived expiry, arbitration, quarantine, cross-device behaviour, history |
| `DATA_MODEL.md` | Persistence models, CloudKit constraints, UUID associations, staging store, indexes, migrations |
| `ICLOUD_SYNC.md` | Container setup, local-first flows, propagation, dual ingress, conflicts, stale updates, watch sync, spike results |
| `DESIGN_SYSTEM.md` | Adaptive surfaces, Liquid Glass rules on 26+, material fallback, tokens, typography, symbols, accessibility, per-platform divergence |
| `TESTING.md` | Per-layer strategy, injected `TimeSource`, fake transport, pre-completion checks |
| `ROADMAP.md` | Milestones, dependency order, live status |
| `DECISIONS.md` | ADRs — see below |

**Documentation rule.** Any change to package boundaries, domain responsibilities, data model, timer or
task behaviour, sync, conflict resolution, target structure, testing strategy, design system, or
roadmap status updates the relevant `docs/` file **and** `memory.md` in the *same* session.

**Fourteen ADRs to be written in Milestone 0** (format: Decision / Date / Status / Context / Options /
Chosen / Why / Consequences):

001 separate Task and Timer packages · 002 SwiftData+CloudKit over Core Data/CKSyncEngine ·
003 event-sourced timer state · 004 optional `UUID` task reference · 005 derived `ActiveTimerState`
and `TimerSession` · 006 expiry derived, never an event · 007 dual ordering — Lamport for
intra-session causality, wall clock for inter-session arbitration, with permanent supersession ·
008 CloudKit-primary watch sync and the dual-ingress staging store · 009 the `AppFeature` package and
per-target composition roots · 010 no `SharedCore` · 011 `DayKey` on `Task` rather than a schedule
entity · 012 "Pool" as terminology · 013 no synchronised derived records — history is folded ·
014 deployment floor iOS 18 / macOS 15 / watchOS 11 with conditional Liquid Glass.

## 31. Milestone 0 actions (post-approval)

1. Create `TaskTracker.xcworkspace` and `TaskTracker.xcodeproj` with three app targets (watchOS
   embedded in iOS, running independently), five local SPM packages, Swift 6.2 strict concurrency
   everywhere, deployment targets **iOS 18 / macOS 15 / watchOS 11**, bundle prefix
   `com.diwan.TaskTracker`.
2. Create package skeletons whose manifests **encode the dependency rules** (§8) — empty targets, no
   implementation.
3. Write `CLAUDE.md`, `AGENTS.md`, `memory.md`.
4. Write the ten `docs/` files, including ADRs 001–014.
5. Configure the CloudKit container `iCloud.com.diwan.TaskTracker` and entitlements across all three
   targets; **freeze the two-entity schema on paper** before any `@Model` exists (R-2).
6. **Run spike R-1**, which measures three things — latency alone would validate the least dangerous
   assumption:
   - **Latency:** propagation of a trivial record Mac → iPhone → Watch, foreground and background,
     device asleep and awake. Numbers recorded in `ICLOUD_SYNC.md`.
   - **Duplicate delivery:** whether the same record is ever observed twice after a forced resync or
     reinstall. Dedupe (§10) assumes it can happen; confirm it.
   - **Concurrent insert behaviour:** two devices inserting sibling records offline, then
     reconnecting — confirming that appends genuinely do not merge, the assumption the entire event-log
     decision rests on (§14).

   **The spike runs on minimum-OS targets, not just on Xcode 26.** Compiling against the iOS 26 SDK
   proves nothing about how SwiftData+CloudKit mirroring behaves on the floor releases, and watchOS 11
   is the least-exercised configuration in the entire plan. Required matrix:

   | Platform | Floor (must pass) | Current (should pass) |
   |---|---|---|
   | macOS | 15 Sequoia | 26 Tahoe |
   | iOS | 18 | 26 |
   | watchOS | **11 — including a real device, not only the simulator** | 26 |

   watchOS 11 on real hardware is non-negotiable here: background CloudKit delivery to a sleeping
   watch is exactly what R-1 exists to measure, and the simulator does not model it.

   This is the only code Milestone 0 produces, and it is deleted afterwards.
7. Verify: all three targets build clean with zero warnings; the dependency graph is compiler-enforced
   (a deliberate `import TaskDomain` inside `TimerDomain` must fail the build).

**Exit criterion:** implementation can begin without re-litigating the foundation.

## 32. Development milestones

| M | Name | Contents | Tier |
|---|---|---|---|
| 0 | Foundation | Workspace, packages, docs, CloudKit config, spike R-1 | MVP 0 |
| 1 | **TimerDomain** | Events, Lamport, fold, state machine, calculator, arbitration, exhaustive tests. **No UI, no persistence.** | MVP 0 |
| 2 | TaskDomain | Model, `DayKey`, services, repository protocols, tests | MVP 0 |
| 3 | AppData (local) | SwiftData models, indexes, repositories, mapping, in-memory + migration tests. **No CloudKit.** | MVP 0 |
| 4 | **Convergence proof** | CloudKit mirroring on; **throwaway two-device shells** (Mac + iPhone) doing nothing but start/pause/resume; F8 proven on real hardware, including two-offline-starts, supersession permanence and duplicate delivery; schema promoted | MVP 0 |
| 5 | macOS app | `MenuBarExtra`, Today, timer controls, quick-add, Pool search, preferences, `AppFeature` controllers, `AppDesign` v1 with adaptive surfaces | MVP 1 |
| 6 | iOS app | Tabs, Today, Pool, Timer, task editing, timer presets, expiry notification | MVP 1 |
| 7 | watchOS app | Standalone target, two screens, timer controls, R-1 re-measured; WC fast-path only if the numbers demand it | MVP 2 |
| 8 | Reliability | Conflict scenarios end-to-end, long-offline recovery, edge-case sweep, history + per-task totals (F9) | MVP 2 |
| 9 | Polish | Liquid Glass audit on 26+, material-fallback verification, layered app icon, accessibility pass | MVP 2 |

**Milestone 4 is the most important scheduling decision here.** An earlier ordering built the entire
macOS app before any two-device synchronisation existed, deferring the project's second-largest risk
behind its largest deliverable. The shells built here are deliberately disposable — two buttons and a
label — because their job is to prove convergence, not to look like anything. If the conflict model is
wrong, it is found here, with no UI depending on it.

**Timer presets** (15/25/30/45/60) land in Milestone 6 with the iOS app — they are cheap and are what
makes a focus timer pleasant to use daily. MVP 0 shells use raw duration entry.

## 33. Exact recommended implementation order — and why it differs from the obvious one

**TimerDomain before TaskDomain. Deliberately.** The instinct is to build the simpler domain first.
That is wrong here. TimerDomain carries essentially all the project's technical risk: the fold, the
state machine, derived expiry, arbitration. TaskDomain is a well-understood CRUD model with one
interesting decision (`DayKey`). Building the risky thing first means that if event-sourcing proves
disproportionate (R-4), we discover it in week two with nothing built on top — not in month three with
three UIs depending on it.

**Local persistence before sync, but sync before any real UI.** Milestone 3 gives a working local
store, so sync becomes a change to one layer with a baseline to compare against. Milestone 4 then
proves convergence on disposable shells *before* the macOS app is built on it. The two riskiest things
in the project — the fold, and cross-device convergence — are both settled while nothing depends on
them.

**macOS before iOS.** It is the primary surface and the most constrained one. A design that fits a
menu-bar panel will expand to a phone; a design built for a phone will not compress.

**watchOS last.** Least surface area, depends on sync already being proven, and its one open question
(R-1) is best answered against a real two-device system already running.

```
0 Foundation → 1 TimerDomain → 2 TaskDomain → 3 AppData(local) → 4 Convergence proof
  → 5 macOS → 6 iOS → 7 watchOS → 8 Reliability → 9 Polish
```

Milestones 1 and 2 are independent and could run in parallel; 3 depends on both. Everything after 3 is
strictly sequential.

---

## Decisions confirmed by the user

1. **Bundle prefix** `com.diwan.TaskTracker`; CloudKit container `iCloud.com.diwan.TaskTracker`.
2. **Deployment floor: one generation below 26 on every platform** — **macOS 15 Sequoia · iOS 18 ·
   watchOS 11** — with **Liquid Glass applied conditionally** on 26+ and a material fallback below
   (§26, R-6, ADR 014). Confirmed explicitly; no platform is exempt from the dual appearance.
3. **Local expiry notification is in scope** (§28).
4. **Timer presets** scheduled at the planner's discretion → **Milestone 6 (MVP 1)**.

## Open questions

**None outstanding.** The deployment floor — the last open item — is now confirmed as one generation
below 26 on every platform: **macOS 15 Sequoia · iOS 18 · watchOS 11**. All four earlier questions
(bundle prefix, floor, expiry notification, preset scheduling) are answered and recorded above.

---

## Deferred to implementation (reviewed, non-blocking)

Raised in review, deliberately not solved here — none affects the schema or an ADR, and each is
cheaper to settle against real code:

1. **Cache-invalidation rule** — the cached projection must be explicitly invalidated on any log
   change (local append, CloudKit remote change, staging insert or prune). Milestone 3.
2. **Q1 result size** — the session-start index is correct but unbounded (one row per session ever).
   At ~1 session/day this is trivial for years; add a local-only materialised index if profiling ever
   says otherwise. Never synced (§12).
3. **Malformed logs** — two `.started` events sharing one `sessionID` should not be possible, but the
   projection must behave sanely if it happens. Define at Milestone 1 as part of totality.
4. **Out-of-order index growth** — a test that a late-arriving `.started` correctly and retroactively
   changes its predecessor's `supersededAt`. Milestone 4.
5. **Notification cancellation on remote supersession** — the local expiry notification (§28) is
   cancelled on local pause/stop/reset, but must also be cancelled when a *remote* superseding
   `.started` arrives via CloudKit or staging. Milestone 6, with the notification itself.

## Review log

- **Draft 6** — Codex round 5. Verdict: **cleared to freeze the two-entity schema and author the 14
  ADRs**, conditional on two wording corrections, both applied here. Blockers 1 and 3 confirmed
  resolved; the session-start index was confirmed correct under eventual consistency (a late-arriving
  `.started` retroactively adjusts its predecessor's boundary, and since nothing derived is cached
  across devices, no device can hold a stale answer).
  1. **`.reset` removed from the quarantine escape hatch** (§10). I had grouped it with `.stopped` as
     "terminal", missing that `.reset` *discards* history while `.stopped` *retains* it — so a stale
     client could have erased history it could not interpret. Only `.stopped` is the guaranteed
     escape; `.reset` joins `.paused`/`.resumed` as withheld. Costs the user nothing, since `.stopped`
     already provides a complete escape. General rule recorded: when choosing what to expose to a
     client that understands less, prefer the retaining operation over the discarding one.
  2. **Post-stop result corrected to `.idle`** (§10). My own sentence said a "next-greatest session"
     takes over, contradicting §20's irreversible supersession and the worked example there. §20 is
     canonical: terminating the maximum never revives a displaced session.
- **Draft 5** — Codex round 4 (3 of 5 fixes fully resolved; 3 new blockers, all genuine errors of
  mine). Resolved:
  1. **Supersession cutoff** (§28). Draft 4 claimed a session's projection depends only on its own
     events. False for any superseded session: its elapsed time is truncated at its successor's start,
     and that instant lives *outside* it. Projection now takes an explicit
     `supersededAt: Date?` boundary, sourced from the Q1 start-index (entry *i*'s boundary is entry
     *i+1*'s `startedAt`, `nil` for the last). The active session always has `nil`, which is why the
     current-state path never exposed the bug — but per-task totals would have been silently wrong.
  2. **Quarantine escape made truthful** (§10). Draft 4's "a fresh `.started` always supersedes" is
     false against a future-skewed quarantined winner: the fresh start sorts *behind* it and is
     immediately superseded, leaving the user unable to pause, stop, or replace the timer. Fixed by
     permitting `.stopped` into a quarantined session — a terminal event whose
     effect does not depend on the session's interior, unlike `.paused`/`.resumed`. This establishes
     a stated product guarantee: **the user can always stop whatever timer is active.**
  3. **Type contradiction resolved** (§12). `ActiveTimerState` lacked a `.completed` case that §10 and
     §18 both produced. The canonical enum is now spelled out with `.idle` / `.active` / `.completed`,
     and the reason `.completed(.expired)` must not collapse into `.idle` is stated.
  4. **Editorial sweep** of stale pre-split "fold" wording: §12 source column, §17 and §21 view
     rendering (`evaluate(at:)` per tick over a cached projection), §18 "identically for the same
     `at`", §28 "next evaluation", R-6 widened to component-level seam. Q1/Q2 now explicitly read the
     synced+staging union, and property tests extended to duplicates, `deviceID` ties, and
     mixed-version logs.
- **Draft 4** — Codex round 3 (verdict: 6 of 9 resolved, 3 partial, plus 2 gaps on the new OS floor).
  All five remaining points specified:
  1. **Projection/evaluation split** (§10, §18) — Draft 3 called expiry "derived" while computing it
     with `now >= deadline` inside the fold, contradicting the log-only invariant stated two sections
     earlier. Now `project(events)` is timeless and `evaluate(projection, at:)` is time-dependent,
     pure, and writes nothing. §2.7 reworded to match, and a timelessness property test added.
  2. **Bounded-query correctness** (§28) — the `occurredAt >= greatestStart` filter was wrong (a
     skewed clock can place a session's own `.paused` before its start). Replaced with decomposition
     by `sessionID`: Q1 arbitrates via `#Index(kind, occurredAt, deviceID)` with `fetchLimit 1`, Q2
     fetches the winning session's events. Equivalence to the full-log fold argued *and* asserted as
     a randomised property test against a reference implementation.
  3. **Quarantine completed** (§10) — recomputed rather than stored, so it lifts automatically on
     update; `.started` remains authorable so a stale device is never locked out; and the
     global-arbitration hole is closed by reserving `.started` as a permanently stable kind with
     additive-only fields, so arbitration is computable by any client of any age without interpreting
     unknown kinds.
  4. **AppDesign seam widened** (§26) — modifiers alone cannot express Liquid Glass's *structural*
     differences, so the seam is now component-shaped: `SurfaceGroup`, `AppToolbar`, `AppTabView`,
     `.contentScrollEdge()` alongside the surface modifiers, with both appearances treated as
     first-class.
  5. **Minimum-OS testing made explicit** (§31) — spike R-1 now runs a floor-vs-current device
     matrix, with watchOS 11 on real hardware called out as non-negotiable.
- **Draft 3** — user decisions incorporated (bundle ID, deployment floor with conditional Liquid Glass,
  notification confirmed, presets scheduled), plus Codex round-2 corrections. Rewritten rather than
  patched, because patching Draft 1 → 2 is what produced the internal contradictions Codex found.
  1. **Supersession made permanent and monotone** (§20). Draft 2 arbitrated only "when more than one
     session is currently non-terminal", which would let a superseded session resurrect once the winner
     stopped. Now: every session earlier than the greatest `.started` is permanently terminated at the
     instant it was displaced.
  2. **Receiver-relative skew guard removed** (§20). It made the fold depend on the receiving device's
     clock, so two devices could compute different winners from an identical log — breaking convergence.
     Skew is now handled at authoring time only, and §2.7/§10 state the invariant explicitly.
  3. **`TimerSessionRecord` contradiction resolved** — §12, §14 and §20 now agree: the synced schema is
     exactly `TaskRecord` + `TimerEventRecord`, and history is folded.
  4. **Dual-ingress given real storage semantics** (§16) — WC events land in a separate non-mirrored
     staging container, so a WC-received event is never re-mirrored to CloudKit by the receiver.
  5. **Forward compatibility strengthened** (§10) — `kind` as `String`, skip-don't-delete, and session
     **quarantine** so a stale client cannot author into a session it cannot project.
  6. **Lamport mechanics specified** (§10) and **bounded query strategy** added (§28).
  7. **Compaction explicitly not half-designed** (§28) — deferred to its own post-MVP ADR, with the
     data-loss hazard stated.
  8. **Document consistency** — status, ADR count (14) and MVP tiers reconciled across all sections.
- **Draft 2** — Codex round 1: split Lamport/wall-clock orderings; removed synced snapshots; corrected
  `AppFeature` composition root; added dual-ingress rule and event schema versioning; inserted the
  Milestone 4 convergence proof and widened spike R-1.
- **Draft 1** — initial architecture and roadmap. Advisor review: expiry made derived rather than an
  event; fold dedupe required; superseded-session preservation made explicit; watch latency downgraded
  from assumption to measured risk with a transport seam; compaction deferred.
</content>
