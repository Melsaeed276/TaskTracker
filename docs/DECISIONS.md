# Architecture Decision Records

These accepted records expand the fourteen decisions frozen by
[`plan01.md`](../plans/plan01.md), Draft 6. They preserve the approved architecture and its trade-offs.
Sibling documents own operational detail; these records own why each costly-to-reverse choice was
made.

## ADR 001 — Separate Task and Timer packages

### Decision

Keep `TaskDomain` and `TimerDomain` as independent pure Swift packages.

### Date

2026-08-09

### Status

Accepted

### Context

Tasks and timers are related in the product but neither owns the other. A timer can be general, a
task can have many historical sessions, and both domains must evolve independently. A namespace does
not enforce a boundary.

### Options Considered

- Make `Task.activeTimer` a lifecycle-owned child.
- Add a `TaskTimerLink` relationship entity.
- Put both domains in one package under separate namespaces.
- Use two compiler-enforced packages and join them above the domain layer.

### Chosen Approach

Create zero-dependency `TaskDomain` and `TimerDomain` packages. Neither imports the other. Join task
and timer data only in `AppData` using an optional identifier.

### Why

The relationship is optional in both directions and one task can relate to many sessions. Ownership
would block general timers, complicate history, and force a fragile persistence relationship.
Compiler-enforced separation prevents accidental erosion of the model.

### Consequences

- Each domain stays pure, testable, and independently evolvable.
- Cross-domain use cases live in `AppFeature`; persistence joins live in `AppData`.
- A small amount of mapping is required at the boundary.
- The packages may duplicate a tiny primitive abstraction rather than couple themselves.

See [`ARCHITECTURE.md`](ARCHITECTURE.md), [`TASK_ARCHITECTURE.md`](TASK_ARCHITECTURE.md), and
[`TIMER_ARCHITECTURE.md`](TIMER_ARCHITECTURE.md).

## ADR 002 — SwiftData with CloudKit mirroring

### Decision

Use SwiftData with CloudKit private-database mirroring instead of Core Data with CloudKit or raw
CloudKit/CKSyncEngine.

### Date

2026-08-09

### Status

Accepted

### Context

The app is single-user, local-first, offline-capable, and spans macOS, iOS, and watchOS. It needs
background synchronisation without an account system or operated backend. SwiftData+CloudKit has hard
constraints: no custom merge hook, no unique attributes under sync, fragile relationships, and every
synced property must be optional or defaulted.

### Options Considered

- SwiftData + CloudKit mirroring.
- Core Data + `NSPersistentCloudKitContainer`.
- Raw CloudKit or `CKSyncEngine`.
- A hybrid: SwiftData for tasks and raw CloudKit for timers.
- `NSUbiquitousKeyValueStore`.

### Chosen Approach

Use one synced SwiftData container backed by the private CloudKit database and containing exactly
`TaskRecord` and `TimerEventRecord`. Use UUID fields rather than CloudKit relationships. A second
non-synced container exists only for optional WatchConnectivity staging.

### Why

SwiftData supplies local persistence, offline queues, background sync, watchOS support, and migration
machinery at low implementation cost. Its missing conflict hook is neutralised for high-conflict
timer state by immutable event rows. Task edits are low-conflict enough for property-level
last-writer-wins. Core Data uses substantially the same sync engine with worse Swift 6 ergonomics;
raw CloudKit would require building the store, queue, token bookkeeping, and watch path ourselves.

### Consequences

- There is no backend or authentication service to operate.
- Schema constraints are non-negotiable and must be frozen before records exist.
- CloudKit development-to-production promotion is one-way and must be deliberate.
- The architecture depends on the concurrent-insert assumption, which Milestone 0 must prove on
  minimum-OS real devices.
- Raw CloudKit remains the more controllable but much more expensive fallback.

See [`DATA_MODEL.md`](DATA_MODEL.md) and [`ICLOUD_SYNC.md`](ICLOUD_SYNC.md).

## ADR 003 — Event-sourced timer state

### Decision

Represent timer truth as an append-only log of immutable `TimerEvent` records rather than a mutable
active-timer record.

### Date

2026-08-09

### Status

Accepted

### Context

SwiftData's CloudKit mirroring has no application-level merge hook and merges mutable records at
property granularity. Concurrent edits to one `ActiveTimer` could combine properties from distinct
device states into a state nobody authored. A single globally active timer must also survive offline
concurrent actions, duplicate delivery, reordered delivery, relaunch, and long suspension.

### Options Considered

- One mutable `ActiveTimer` record with property-level last-writer-wins.
- A mutable record with optimistic locking or compare-and-swap.
- Raw CloudKit with custom conflict handling.
- Immutable events projected into derived state.

### Chosen Approach

Persist and synchronise only immutable events. Each has stable identity, session identity, kind,
wall-clock instant, author device, Lamport value, and schema version; `.started` additionally fixes
duration and optional task identity. Deduplicate by event ID, deterministically order events, ignore
invalid stale transitions, and project them with pure domain functions. Never mutate or normally
delete an event.

### Why

Immutable sibling rows are appended, not property-merged. The missing CloudKit merge hook stops
mattering because reconciliation occurs after storage in a deterministic fold owned by the app. The
same event set produces the same projection regardless of arrival order or receiving device. The log
also gives offline behaviour, auditability, history, and per-task totals without creating additional
sources of truth.

The alternative mutable row can be torn—for example, one device's paused state can merge with
another device's running start timestamp. Optimistic locking is unavailable through SwiftData
mirroring. Raw CloudKit would buy merge control at the cost of months of sync infrastructure, while
immutability already removes the merge decision.

### Consequences

- The fold is the single highest-risk correctness function and receives the highest test density.
- More types and logic exist than in a mutable-row design.
- Duplicates must be tolerated because CloudKit sync cannot enforce a unique attribute.
- Projection must be idempotent, order-independent, total, and log-only.
- Events preserve losing concurrent work instead of silently deleting it.
- Storage grows monotonically. Expected volume is small; compaction is deferred because safe deletion
  needs tombstones and its own future ADR.
- Milestone 4 must reassess complexity against the defined fallback of mutable state plus accepted
  last-writer-wins risk, without changing repository protocols.

See [`TIMER_ARCHITECTURE.md`](TIMER_ARCHITECTURE.md) and [`TESTING.md`](TESTING.md).

## ADR 004 — Optional UUID task reference

### Decision

Associate a timer session with a task using immutable `relatedTaskID: UUID?` on `.started`.

### Date

2026-08-09

### Status

Accepted

### Context

Timers can be general or task-related, and historical sessions must survive task deletion. A typed
task reference would make `TimerDomain` depend on `TaskDomain`; a persistence relationship would
violate the CloudKit model constraints.

### Options Considered

- A CloudKit/SwiftData relationship.
- A `TaskReference` protocol shared across domains.
- A join entity.
- An optional opaque UUID fixed on the start event.

### Chosen Approach

Store `relatedTaskID: UUID?` only on `.started`, immutable for the session lifetime. Resolve the join
in `AppData`; display a missing task as “Deleted task.”

### Why

A UUID is the smallest primitive both domains understand without coupling. Immutability preserves
what the user was doing at the time and keeps historical totals honest. Deliberately weak referential
integrity avoids a fragile synced relationship.

### Consequences

- General timers use `nil` naturally.
- Deleted tasks leave safe dangling IDs and preserved history.
- `AppData` must resolve identifiers and missing records.
- The database cannot enforce referential integrity, by design.

See [`TASK_ARCHITECTURE.md`](TASK_ARCHITECTURE.md) and [`DATA_MODEL.md`](DATA_MODEL.md).

## ADR 005 — Derive TimerSession and ActiveTimerState

### Decision

Keep `TimerSession` and `ActiveTimerState` as distinct derived domain values; store neither.

### Date

2026-08-09

### Status

Accepted

### Context

A session is one permanent focus run, while active state is the momentary global selection. Treating
them as one type confuses cardinality and lifetime; storing them introduces multiple writable
representations of the same events.

### Options Considered

- Store both as mutable independent records.
- Store a terminal session snapshot.
- Collapse completed into idle.
- Derive sessions and active state from events.

### Chosen Approach

Derive `TimerSession` per session and derive `ActiveTimerState` as `.idle`, `.active(session, phase)`,
or `.completed(session, reason)`, where reason is expired, stopped early, or superseded.

### Why

The distinction matches the product: many durable sessions but zero or one active timer. A completed
expired state must remain visible long enough to communicate completion; it is not the same as idle.
Derivation prevents disagreement between snapshots and their source log.

### Consequences

- Relaunch and history reconstruct state from events.
- No synchronised snapshot can become stale or torn.
- Projection and evaluation cost is paid on read, mitigated by bounded queries and optional
  local-only caches.

See [`TIMER_ARCHITECTURE.md`](TIMER_ARCHITECTURE.md).

## ADR 006 — Derive expiry; never emit an expiry event

### Decision

Determine expiry during pure evaluation at a supplied instant. Do not define `.finished` or persist
an automatic expiry event.

### Date

2026-08-09

### Status

Accepted

### Context

A timer can reach its deadline while every device and process is asleep. Expiry is a consequence of
the start, duration, pauses, and time—not a user-authored action. Requiring an event would require a
device to claim authorship after waking.

### Options Considered

- Have the first awake device append `.finished`.
- Let every device append expiry and deduplicate later.
- Run a background process expected to stay alive.
- Derive expiry from the projected deadline at evaluation time.

### Chosen Approach

`project(events, supersededAt:)` remains timeless. `evaluate(projection, at:)` returns
`.completed(.expired)` when a running session's deadline is at or before `at`. Evaluation writes
nothing. Only `.stopped` and `.reset` are authored terminal events.

### Why

An expiry during global sleep has no author. Automatic events would make devices race on wake,
creating duplicate or conflicting records for a deterministic consequence. Derivation works after
arbitrary downtime and does not rely on a running process. Separating timeless projection from
time-dependent evaluation preserves convergence: clock skew can create only a transient display
difference, never divergent persisted truth.

### Consequences

- There is no `.finished` kind or expiry write.
- A device can reconstruct expiry immediately after relaunch or a week asleep.
- Skewed clocks may briefly disagree at the deadline; this is accepted because evaluation is pure.
- Local notifications are scheduled presentation effects, not synchronised truth, and may require
  cancellation when a remote superseding start arrives.
- Tests inject `at` and never wait in real time.

See [`TIMER_ARCHITECTURE.md`](TIMER_ARCHITECTURE.md), [`ICLOUD_SYNC.md`](ICLOUD_SYNC.md), and
[`TESTING.md`](TESTING.md).

## ADR 007 — Dual ordering and permanent supersession

### Decision

Order events within a session by `(lamport, occurredAt, deviceID)`, arbitrate sessions by
`(startedAt, deviceID)`, and make every displacement permanent.

### Date

2026-08-09

### Status

Accepted

### Context

Session actions are usually causally related; starts on partitioned devices can be causally
concurrent. A single order cannot answer both “what happened inside this session?” and “which start
expresses the latest global intent?” CloudKit provides no distributed lock, so two offline starts
cannot be prevented.

### Options Considered

- Use Lamport order for both intra-session sequencing and inter-session arbitration.
- Use wall-clock time for both.
- Use CloudKit server modification/upload order.
- First-start-wins.
- Prompt the user to resolve every conflict.
- Latest wall-clock start wins, with permanent loser preservation.

### Chosen Approach

Use Lamport first within one session because it records causal knowledge; use wall-clock
`startedAt`, with `deviceID` as a total tiebreak, between sessions because independent Lamport values
are incomparable. The greatest start is the only session that may be active. Every preceding session
is irreversibly `.superseded` at its immediate successor's start and retained in history.

### Why

Lamport encodes what a device had seen, not when the user acted. A busy Mac can have counter 500 and
an offline iPhone counter 3; that cannot make the Mac's earlier start more recent. Conversely,
wall-clock skew must not reorder a resume before a causally known pause within one session. Server
time measures delivery rather than intent. Latest-start-wins best represents the user's most recent
explicit command.

Permanent supersession prevents resurrection. If arbitration considered only currently non-terminal
sessions, stopping the winner would expose a replaced timer again. The successor's `startedAt`
therefore becomes the loser's irreversible cutoff even if the successor later stops, resets, or
expires.

### Consequences

- Every device with the same log chooses the same winner without a central lock.
- The loser is preserved with real elapsed time; there is no silent data loss.
- A superseded session's projection requires the successor's external `supersededAt` boundary.
- Stopping the maximum yields `.idle`; no next-greatest session revives.
- Device clock error can influence inter-session intent. It is surfaced at authoring time only;
  receiver-relative filtering is forbidden because it would break convergence.
- `deviceID` must be stable enough to provide a deterministic tie, but grants no priority.
- The system resolves conflicts deterministically rather than showing an MVP merge prompt.

Example: Mac starts A at 14:00/Lamport 5 and iPhone starts B at 14:10/Lamport 3. B wins on wall clock;
A is superseded at 14:10 and retains ten minutes. Stopping B yields idle, never A.

See [`TIMER_ARCHITECTURE.md`](TIMER_ARCHITECTURE.md) and [`TESTING.md`](TESTING.md).

## ADR 008 — CloudKit-primary Watch sync with local dual-ingress staging

### Decision

Use CloudKit as the primary Watch transport; add WatchConnectivity only if measured latency requires
it, and stage WC-received events in a separate non-synced store.

### Date

2026-08-09

### Status

Accepted

### Context

The Watch app runs independently and a paired reachable phone is not guaranteed. CloudKit latency to
a sleeping Watch may nevertheless be too slow for controls to feel responsive. If one logical event
arrives through WC and CloudKit, inserting both paths into the synced store would cause the receiving
device to re-mirror a fact it did not author.

### Options Considered

- WatchConnectivity as primary transport.
- CloudKit only with no seam.
- Hybrid transports from day one.
- CloudKit primary, measurement-gated WC fast path, separate staging store.

### Chosen Approach

Only the authoring device writes an event to the synced store. If added, WC preserves the original
event metadata and inserts it into a non-mirrored staging container. Projection reads the deduplicated
union; the staging copy is pruned when CloudKit delivers the canonical row.

### Why

CloudKit supports independent operation and remains the correctness path. WC is opportunistic.
Separate staging prevents the receiver from becoming a second author and prevents duplicate
persistence while still offering a faster view of the same fact.

### Consequences

- Milestone 0 must measure foreground/background latency, duplicates, and concurrent inserts,
  including watchOS 11 real hardware.
- A second local container and pruning logic add complexity only if WC is introduced.
- Ignoring every WC message must still converge identically.
- WC can improve latency but never becomes a correctness dependency.

See [`ICLOUD_SYNC.md`](ICLOUD_SYNC.md) and [`DATA_MODEL.md`](DATA_MODEL.md).

## ADR 009 — AppFeature package and per-target composition roots

### Decision

Place shared observable controllers and use cases in `AppFeature`; keep a separate composition root
inside each app target.

### Date

2026-08-09

### Status

Accepted

### Context

Starting a timer for a task involves validation, repository calls, optimistic local updates, and
error surfacing. Duplicating this across macOS, iOS, and watchOS would drift. Yet three executables
have different scenes, adapters, and lifecycles, so they cannot share one composition root.

### Options Considered

- Duplicate controllers per app.
- Put presentation state in `AppData`.
- Put controllers in `AppDesign`.
- Add `AppFeature` and retain per-target construction.

### Chosen Approach

`AppFeature` contains only `@Observable` presentation controllers and use cases, depending on both
domains and `AppData`. Each `@main` target constructs its own `AppEnvironment` and injects platform
adapters. `AppDesign` remains visual and model-agnostic.

### Why

This centralises cross-platform application behaviour without confusing presentation, persistence,
and visual layers. Per-target roots acknowledge genuinely distinct executable lifecycles.

### Consequences

- Shared behaviour is implemented once.
- Each target retains explicit construction code.
- The package needs an anti-drift review: reusable stateless rules belong in domains; visuals belong
  in `AppDesign`.

See [`ARCHITECTURE.md`](ARCHITECTURE.md).

## ADR 010 — Do not create SharedCore

### Decision

Do not add a `SharedCore` package.

### Date

2026-08-09

### Status

Accepted

### Context

The two domains currently overlap only in a tiny time abstraction and a few small protocols. A
shared package would couple domains that the architecture deliberately separates.

### Options Considered

- Centralise all shared primitives immediately.
- Duplicate the few trivial abstractions.
- Defer a shared package until repeated evidence exists.

### Chosen Approach

Keep the packages separate and tolerate tiny duplication. Revisit only when three or more distinct,
genuine abstractions are duplicated.

### Why

A four-line protocol is cheaper than a dependency that becomes a dumping ground and weakens the
compiler-enforced boundary. The threshold makes reconsideration evidence-based.

### Consequences

- Some small types may appear twice.
- Domain independence remains obvious and enforceable.
- Future consolidation requires meeting the stated threshold, not preference alone.

See [`ARCHITECTURE.md`](ARCHITECTURE.md).

## ADR 011 — DayKey on Task

### Decision

Represent Today assignment as optional `scheduledDay: DayKey?` on `Task`, not a schedule entity or
instant.

### Date

2026-08-09

### Status

Accepted

### Context

“Today” is a calendar fact, not a universal instant. Timezone travel and daylight-saving changes can
move a `Date` across civil-day boundaries. Multi-day scheduling and recurrence are out of scope.

### Options Considered

- `Date` at local midnight.
- `isInToday: Bool`.
- A `TaskSchedule` entity.
- ISO `yyyy-MM-dd` `DayKey?` on `Task`.

### Chosen Approach

Resolve the device's current calendar at assignment time and store the ISO day key on the task.
`nil` means unscheduled.

### Why

The key remains the same calendar day through travel and DST. A boolean cannot express tomorrow and
needs nightly clearing. A schedule entity would add a CloudKit relationship for recurrence features
the MVP does not have.

### Consequences

- Today and Pool queries are simple and calendar-stable.
- Recurrence later requires an additive schedule entity and backfill.
- Assignment intentionally reflects the calendar context at the moment of assignment.

See [`TASK_ARCHITECTURE.md`](TASK_ARCHITECTURE.md).

## ADR 012 — Use “Pool” terminology

### Decision

Call the durable reservoir of unscheduled incomplete tasks the “Pool.”

### Date

2026-08-09

### Status

Accepted

### Context

The collection is meant to remain full and supply Today repeatedly. “Inbox” implies a queue that
must be triaged to zero; “Backlog” implies prioritised committed work. Both create the wrong mental
model.

### Options Considered

- Inbox.
- Backlog.
- Pool.

### Chosen Approach

Use Pool in product copy and documentation. Define it as the query
`scheduledDay == nil && completedAt == nil`, not as a container.

### Why

Pool is the user's own term and accurately conveys a durable reservoir of ideas without guilt or a
commitment signal.

### Consequences

- Terminology aligns with intended behaviour.
- The model has no Pool entity or membership flag.
- Product copy must explain the term consistently.

See [`PRODUCT.md`](PRODUCT.md) and [`TASK_ARCHITECTURE.md`](TASK_ARCHITECTURE.md).

## ADR 013 — No synchronised derived records

### Decision

Synchronise only source facts. Fold timer history from events; do not synchronise session snapshots,
active-state records, totals, remaining time, elapsed time, or other derived records.

### Date

2026-08-09

### Status

Accepted

### Context

An earlier design materialised a `TimerSessionRecord` when a session ended. Multiple devices can
derive and write that record for the same source session. Under property-level CloudKit merging, the
snapshot becomes another mutable conflict surface and another representation that can disagree with
the immutable log. Per-second values are already stale when received and would generate thousands of
writes.

### Options Considered

- Synchronise active state and per-second countdown values.
- Materialise and synchronise terminal session snapshots.
- Synchronise per-task aggregates.
- Fold all derived values from immutable events, allowing local-only caches after profiling.

### Chosen Approach

The synced schema contains exactly `TaskRecord` and `TimerEventRecord`. `TimerSession`,
`ActiveTimerState`, history, elapsed/remaining values, completion by expiry, and per-task totals are
derived. History projects each session using its own events plus the successor-supplied
`supersededAt` cutoff. Any future cache or materialised index must be local-only, never mirrored, and
invalidated whenever the source log changes.

### Why

One shared fact must have one synchronised representation. A derived record written by several
devices hands CloudKit the same property-level merge problem event sourcing was chosen to avoid. It
can be stale, torn, or disagree with a newly arrived event. Folding is deterministic, bounded by Q1
and Q2, and cheap at expected volume. Timestamps remain valid in transit; countdown numbers do not.

The supersession boundary is essential: a displaced session's elapsed time ends at the successor's
start, which exists outside its own events. Folding history with that boundary preserves exact totals
without a writable snapshot.

### Consequences

- The synced schema stays minimal and has no duplicate source of timer truth.
- A one-hour timer produces a handful of writes rather than 3,600 countdown updates.
- Reads perform projection work; bounded queries and cached projections control cost.
- A local cache must have explicit invalidation for local appends, CloudKit changes, staging inserts,
  and staging pruning.
- Reinstall discards local caches harmlessly and reconstructs them from CloudKit.
- If profiling shows history is slow, optimisation is constrained to local-only derived data.

See [`TIMER_ARCHITECTURE.md`](TIMER_ARCHITECTURE.md) and [`DATA_MODEL.md`](DATA_MODEL.md).

## ADR 014 — Deployment floors and conditional Liquid Glass

### Decision

Support macOS 14, iOS 17, and watchOS 10 as deployment floors; use Liquid Glass only on version 26
and newer, with first-class material fallbacks.

### Date

2026-08-09 (revised twice 2026-08-09 — see Revision and Revision 2 below)

### Status

Accepted (revised)

### Context

The confirmed product requirement is broad real-device reach, including hardware that cannot run
OS 26. Liquid Glass APIs are available only on 26+, and their differences can be structural rather
than a simple background modifier.

### Options Considered

- Require version 26 everywhere.
- Avoid Liquid Glass entirely.
- Scatter availability checks through feature views.
- Gate appearance inside component-shaped `AppDesign` seams.

### Chosen Approach

Set floors to macOS 14, iOS 17, and watchOS 10 (see Revision 2). `AppDesign` exposes semantic
modifiers and availability-gated containers/components that select Liquid Glass on 26+ and
material-based designs on the floor releases. Feature code does not branch on OS version.

### Why

The floors honour real-device reach — including an iPhone 11 capped at iOS 18.6.2 — while allowing
the current visual language where 26 is available. Centralising the seam prevents availability
logic from spreading and acknowledges that glass grouping, toolbars, and tab behaviour can differ
structurally.

### Consequences

- Every surface has two supported appearances across three platforms.
- Design and accessibility verification must cover both paths.
- `AppDesign` carries extra component-level compatibility work.
- Minimum-OS builds and real-device testing at the floor are required; building only against SDK 26
  does not prove floor behaviour.

### Revision — 2026-08-09

**Original decision** (floors: macOS 15 / iOS 18 / watchOS 11, dual appearance via `AppDesign`
compatibility seam) is superseded. The floor was set before checking available hardware: the only
paired Apple Watch is a Series 6 on watchOS 26.0, and Xcode's installed watchOS SDK (26.5) doesn't
ship a matching 11.x simulator runtime by default either, so a watchOS 11 floor could not be verified
on real hardware — exactly the guarantee ADR 014 exists to make (spike R-1 requires "watchOS 11 —
real hardware"). Rather than ship an unverified floor with a compatibility seam paying for two
appearances, the floor is raised to 26 everywhere, deleting the seam entirely: it matches the only
real device available and removes a whole class of availability-gating work with nothing to show for
it. `AppDesign` had not yet implemented any compatibility-seam code (Milestone 0/skeleton only), so
this is a documentation and `project.yml` correction, not a code rollback.

**Consequences of the revision:** superseded same day — see Revision 2.

### Revision 2 — 2026-08-09

The 26-everywhere revision above was itself made on incomplete information: it checked only the
paired Apple Watch (watchOS 26.0) and never checked the paired iPhones. The full real-device roster
turned out to be:

| Device | OS |
|---|---|
| Mac (dev machine) | macOS 26.5.2 |
| iPhone 13 mini | iOS 26.6 |
| Apple Watch Series 6 | watchOS 26.0 |
| iPhone 11 | **iOS 18.6.2 — hardware-capped, cannot reach 26** |

A 26-everywhere floor silently retires the iPhone 11 as a usable test device. The user's product
requirement is that the app run on all available real devices and simulators, not just the newest
generation, so the floor reverts to macOS 14 / iOS 17 / watchOS 10 — restoring the dual-appearance
compatibility seam this ADR originally specified, deliberately set below every real device's actual
ceiling (iOS 17 is one generation below the iPhone 11's 18.6.2 ceiling) rather than pinned exactly to
it, for headroom. `AppDesign` still has no compatibility-seam code written (Milestone 0/skeleton
only), so this remains a documentation + `project.yml` + package-manifest correction, not a code
rollback.

**Consequences of Revision 2:**
- `project.yml` `deploymentTarget` is macOS 14.0 / iOS 17.0 / watchOS 10.0.
- All five package manifests' `platforms:` match: `.iOS(.v17), .macOS(.v14), .watchOS(.v10)`.
  `swift-tools-version: 6.2` is kept (harmless at a lower floor, and avoids re-touching every
  manifest header again if the floor changes a third time).
- `docs/DESIGN_SYSTEM.md` and spike R-1's device matrix (`docs/ICLOUD_SYNC.md`) target the
  floor-vs-current split again (restored), not 26-everywhere.
- Milestone 9's material-fallback verification step is restored.
- Real-device verification at the floor should include the iPhone 11 (iOS 18.6.2) specifically,
  since it's the device that motivated this reversal.

See [`DESIGN_SYSTEM.md`](DESIGN_SYSTEM.md), [`ARCHITECTURE.md`](ARCHITECTURE.md), and
[`TESTING.md`](TESTING.md).
