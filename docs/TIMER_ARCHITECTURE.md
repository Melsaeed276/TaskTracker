# Timer Architecture

This document is the durable specification for the timer domain. The approved source is
[`plan01.md`](../plans/plan01.md), Draft 6. It defines timer truth, projection, evaluation, conflict
resolution, forward compatibility, cross-device behaviour, and history. Persistence details belong
in [`DATA_MODEL.md`](DATA_MODEL.md), transport details in [`ICLOUD_SYNC.md`](ICLOUD_SYNC.md), and
required properties in [`TESTING.md`](TESTING.md).

## Governing guarantees

The timer is shared logical state, not a running process. Mac, iPhone, and Watch are three views of
one timer. The system therefore guarantees that:

- timestamps and immutable user actions are synchronised; remaining or elapsed seconds never are;
- devices with the same event log produce the same projection;
- evaluation at a supplied instant is pure and persists nothing;
- concurrent starts resolve deterministically without deleting the loser;
- superseded sessions never revive;
- the user can always stop whatever timer is active; and
- offline operation is normal: actions commit locally and synchronise later.

## TimerDomain boundary and responsibilities

`TimerDomain` is a pure Swift package with zero dependencies beyond the Swift standard library and
Foundation. It does not import SwiftUI, SwiftData, CloudKit, WatchConnectivity, `TaskDomain`, or an
app target. It owns:

- `TimerEvent`, `TimerEventKind`, `TimerSession`, `ActiveTimerState`, and `TimerPhase`;
- the timeless `TimerProjection` fold;
- `TimerCalculator`, which evaluates a projection and calculates elapsed and remaining time;
- `TimerTransition`, which defines valid state transitions and ignores stale ones;
- `SessionArbitration`, which chooses the globally winning session;
- the `TimerEventRepository` protocol;
- `TimeSource` and Lamport-clock mechanics.

It owns all timer arithmetic and business rules. Views render plain values and never calculate timer
state. `AppData` maps persisted records to these domain values; `AppFeature` coordinates use cases;
app targets compose dependencies and render the result. See [`ARCHITECTURE.md`](ARCHITECTURE.md).

`TimeSource` is deliberately not named `Clock`, because Swift already defines `Clock`:

```swift
protocol TimeSource: Sendable {
    var now: Date { get }
}
```

Time is injected. No domain test waits in real time.

## The only synchronised timer fact: TimerEvent

The timer is represented by an append-only log of immutable events. Each `TimerEvent` contains:

| Field | Meaning |
|---|---|
| `id` | Globally stable event identity, used for deduplication. |
| `sessionID` | Identity of the focus session to which the event belongs. |
| `kind` | Persisted `String` identifying the event kind. |
| `occurredAt` | Authoring device's wall-clock instant. On `.started`, this is `startedAt`. |
| `deviceID` | Stable authoring-device identifier and deterministic final tiebreak. |
| `lamport` | Causal sequence value stamped when authored. |
| `schemaVersion` | Event schema understood by the authoring build. |
| `duration` | Present on `.started` only; immutable for the session lifetime. |
| `relatedTaskID` | Optional `UUID`, present on `.started` only; immutable thereafter. |

The known kinds are `.started`, `.paused`, `.resumed`, `.stopped`, and `.reset`. There is no
`.finished`; expiry is derived. `.started` alone carries `duration` and `relatedTaskID`, making the
session's initial intent stable. The optional task identifier keeps `TimerDomain` independent of
`TaskDomain`; association and deleted-task display are resolved in `AppData`.

`.stopped` means the user finished early and the elapsed work remains in history. `.reset` means
“that did not happen”: it terminates the session, returns to idle, and discards its elapsed time from
history. That distinction is why both events exist.

### Why the log is append-only

SwiftData with CloudKit mirroring exposes no custom conflict-resolution hook and merges mutable
records at property granularity. A mutable `ActiveTimer` row can therefore be torn into a state that
no device ever authored—for example, one device's `state = paused` combined with another device's
newer `startedAt`, producing a paused timer with a running start time. There is no API at the merge
boundary to reject that combination.

Immutable events are never merged with one another. Concurrent devices append sibling rows; they do
not co-author properties of one row. Reconciliation is consequently a pure function owned by
`TimerDomain` and can be tested exhaustively. History, offline behaviour, per-task totals, and a
debuggable account of what happened follow from the same representation.

The honest cost is more domain types than a mutable row and a fold whose correctness is critical.
The mitigation is purity and the highest test density in the project. Events are never mutated or
deleted in normal operation. Compaction is outside MVP because safe deletion across long-offline
CloudKit clients requires a real tombstone protocol and a separate future ADR.

## Projection and evaluation: the load-bearing split

```text
[TimerEvent] -- project(events, supersededAt:) --> SessionProjection
    persisted          TIMELESS; log only

SessionProjection -- evaluate(projection, at:) --> ActiveTimerState
                         time-dependent, pure, persists nothing
```

### Projection is timeless

`project(events, supersededAt:)` consults only the log and the explicit supersession boundary derived
from that log. It must not consult:

- a clock;
- the receiving device's identity; or
- event arrival order.

It deduplicates by `id`, sorts deterministically, applies valid transitions, and returns a total
projection even for malformed or stale input. Given the same events and boundary, every device must
produce the same projection regardless of its local time or the route by which events arrived.

### Evaluation sees time but writes nothing

`evaluate(projection, at:)` is time-dependent and pure. At the supplied `at`, it determines whether
the projected session is running, paused, stopped early, superseded, or expired, and calculates
elapsed and remaining time. It never appends an event, updates a record, or stores a snapshot.

Two skewed device clocks can momentarily disagree about whether a just-expired timer has crossed its
deadline. That is not a convergence failure: neither evaluation persists its answer, and the
disagreement disappears when both supplied instants cross the deadline. Allowing time into projection
would be different—it could place divergent state into the shared log. The split is therefore
load-bearing for convergence, not an implementation convenience.

Views can cache a projection until the log changes and reevaluate it locally at 1 Hz. A missed frame
does not cause drift because time is derived from instants rather than accumulated tick by tick.

## Canonical state

Both `TimerSession` and `ActiveTimerState` are derived, never stored independently.
`TimerSession` represents one focus run, past or present. `ActiveTimerState` represents the one
globally selected timer at an instant:

```swift
enum ActiveTimerState {
    case idle
    case active(TimerSession, TimerPhase)
    case completed(TimerSession, CompletionReason)
}

enum TimerPhase {
    case running(since: Date)
    case paused
}

enum CompletionReason {
    case expired
    case stoppedEarly
    case superseded
}
```

`.completed(.expired)` is intentionally distinct from `.idle`: the former supports the “your timer
finished” moment, while idle means there is nothing to show. A superseded session evaluates as
`.completed(.superseded)` in history.

## State machine

```text
idle -- start --> running -- pause --> paused -- resume --> running
                       |                 |
                       +---- stop -------+--> completed(.stoppedEarly)
                       |                 |
                       +---- reset ------+--> idle, history discarded

running/paused -- start --> a new session; previous session is superseded
completed      -- start --> a new running session
completed      -- reset --> idle
```

| From | `start` | `pause` | `resume` | `stop` | `reset` |
|---|---|---|---|---|---|
| idle | new running session | invalid | invalid | invalid | invalid |
| running | new session | paused | invalid | session completed as stopped early; global state idle | idle, discarded |
| paused | new session | invalid | running | session completed as stopped early; global state idle | idle, discarded |
| completed | new running session | invalid | invalid | invalid | idle |

Invalid or stale transitions are ignored rather than thrown. A `.resumed` received after a
`.stopped`, for example, came from a device with incomplete knowledge and must not reopen the
session. `TimerTransition` returns `nil`; the fold remains total and never crashes on arbitrary input.

## Expiry is derived, never authored

There is deliberately no expiry event. A timer that expires while every device sleeps has no author.
If expiry required `.finished`, each device would race to write it on wake, creating duplicates and
potential disagreement about a fact that was not a user decision.

Instead, evaluation derives expiry:

```text
phase == running && at >= startedAt + duration + accumulatedPaused
    => completed(.expired)
```

The result can be reconstructed after a week of suspension without any process having remained
alive. Only `.stopped` and `.reset` are user-authored terminal actions. Local expiry notifications are
a presentation concern described in [`ICLOUD_SYNC.md`](ICLOUD_SYNC.md); they do not become timer
truth.

Elapsed and remaining time are similarly derived:

```text
elapsed(at:)   = accumulatedActive + (running ? at - runningSince : 0)
remaining(at:) = max(0, duration - elapsed(at:))
```

## Lamport mechanics: causality, not chronology

At authoring time:

```text
lamport = 1 + max(lamport of every event currently known locally)
```

The value is immutable after authoring. Because a device learns events through synchronisation, the
counter expresses what that device had seen before it acted. It therefore captures causal knowledge:
a resume written by a device that had already seen a pause can be ordered after that pause even if
its wall clock is skewed.

Lamport values do not express real-world recency. A frequently used device can have a high counter
only because it has observed more history. Comparing independent counters from two partitioned
devices as though they were timestamps is a chronology bug.

## Two orderings for two different questions

| Scope | Ordering | Reason |
|---|---|---|
| Within one session | `(lamport, occurredAt, deviceID)` | Session actions are normally causally related. Lamport must defeat wall-clock skew; the other fields make the order total. |
| Between sessions | `(startedAt, deviceID)` | Offline starts can be causally concurrent. Wall clock represents user recency; Lamport counters from independent histories are incomparable. |

Conflating these orderings breaks intent. Using Lamport for inter-session arbitration could allow a
busy but earlier device to defeat a genuinely later start. Using wall clock as the primary ordering
inside a session could place a causally later resume before a pause because one clock was wrong.

`deviceID` is a deterministic final tiebreak, not a statement about device priority. Server upload
time is not used because it reflects connectivity and delivery order rather than user action.

## Arbitration and permanent supersession

Order all `.started` events by `(startedAt, deviceID)`:

1. The greatest start identifies the only session that may be active.
2. Every earlier session is permanently completed as `.superseded` when its immediate successor
   started.
3. The status of later sessions never reopens an earlier one.

This rule is a pure function of the log and makes supersession monotone and irreversible. A terminal
maximum does not cause an earlier session to take over. In particular, stopping the maximum records
that session as `.completed(.stoppedEarly)` for history while the global active state becomes
`.idle`. A superseded timer must never reappear hours after the user replaced it. Expiry remains
`.completed(.expired)` long enough to support the user-facing completion moment; it likewise never
revives a predecessor.

The loser is retained, not deleted. Its elapsed work and optional task link remain inspectable in
history. Latest-start-wins reflects the user's most recent explicit intent; first-start-wins would
revive a forgotten timer over a deliberate replacement.

### The supersededAt boundary lives outside the session

A superseded session's own events do not record the instant at which a successor displaced it. Its
elapsed time must therefore be cut off using an explicit boundary:

```text
project(events, supersededAt: Date?) -> SessionProjection
```

For session `i` in the total start order, `supersededAt` is session `i + 1`'s `startedAt`; the last
session receives `nil`. This instant comes from the successor's `.started` event and therefore lives
outside the superseded session. Omitting it would make per-task totals silently count an open-ended
interval. The boundary is still timeless because it is derived only from the log.

### Worked conflict example

- Mac, offline, starts A at 14:00 with Lamport 5.
- iPhone, offline, starts B at 14:10 with Lamport 3.
- Both reconnect at 14:20.

B wins because inter-session arbitration uses wall clock: `(14:10, iPhone)` is greater than
`(14:00, Mac)`. A is retained as `.superseded`, cut off at 14:10, and contributes exactly ten minutes
to history. B is active from 14:10. A's higher Lamport value is correctly irrelevant; it only says
that the Mac had observed more events before authoring A. If B is then stopped, the global state is
`.idle`; A never revives. Mac, iPhone, and Watch converge on the same answer.

## Forward compatibility and quarantine

`kind` is persisted as a `String` so unknown kinds deserialize safely. Every event carries
`schemaVersion`. An event whose kind is unknown or whose schema version is newer than the client
understands is skipped by projection and never deleted from storage. An older app must preserve data
it cannot yet interpret.

Skipping alone is unsafe: a stale client could author an interior transition based on an incomplete
session. A session containing any uninterpretable event is therefore quarantined. Quarantine is a
computed predicate over the session's events, never a stored or synchronised flag. After an update
understands the event, recomputation lifts quarantine automatically.

While quarantined:

- `.started` remains authorable because it creates a fresh `sessionID` and does not depend on the
  quarantined session's interior state;
- `.stopped` remains authorable because “this session is over” is safe regardless of whether its
  unknown interior was running or paused, and it retains history;
- `.paused` and `.resumed` are withheld because both require knowledge of interior state; and
- `.reset` is withheld because it discards history. A stale client must not erase history it cannot
  understand when `.stopped` provides a retaining escape.

The escape cannot rely on `.started` alone. A quarantined winner may have a future-skewed
`startedAt`; a genuinely fresh start today could sort behind it and be immediately superseded.
Permitting `.stopped` into the winning quarantined session guarantees termination and then `.idle`.
Thus no clock skew, version skew, or network partition can create an active timer the user cannot
stop.

### Session genesis is permanently stable

`.started` is reserved as the only way to begin a session and must remain permanently stable. Future
schemas may add event kinds but may not add a second genesis kind. The fields `id`, `sessionID`,
`kind`, `occurredAt`, `deviceID`, `lamport`, and `schemaVersion` remain additive-only base fields.

This guarantees that arbitration can always identify every session and its `startedAt` using v1
fields without interpreting unknown interior events. An old client may not understand what happened
inside a newer session, but it can still compute which session exists last in the global start order.

## Bounded queries

The runtime path does not scan the entire event log. It decomposes the definition without changing
its result. Both queries read the deduplicated union of the synced store and any non-synchronised
WatchConnectivity staging store described in [`DATA_MODEL.md`](DATA_MODEL.md).

### Q1: session-start index

Fetch all `kind == "started"` events sorted ascending by `(occurredAt, deviceID)`, backed by an index
on `(kind, occurredAt, deviceID)`. For starts, `occurredAt` is `startedAt`. This produces one totally
ordered `(sessionID, startedAt, deviceID)` entry per session. Its last entry is the arbitration
maximum. Entry `i + 1` also supplies entry `i`'s `supersededAt` boundary.

Q1 is intentionally not replaced with `occurredAt >= greatestStart`: a skewed clock can place a
session's own pause before its start in wall-clock time, and such a filter would silently omit it.
Session identity, not time range, defines membership.

### Q2: winning session events

Fetch every event with `sessionID == winningSessionID`, without a time filter, backed by an index on
`sessionID`. Deduplicate by event `id`, project using Q1's boundary (`nil` for the maximum), then
evaluate at the requested instant.

### Why Q1 + Q2 equals the full-log definition

The reference fold chooses the maximum `.started` by `(occurredAt, deviceID)`; that is exactly Q1's
last entry. A session projection needs only all events carrying its own `sessionID` plus its successor
boundary; Q2 and Q1 supply exactly those inputs. Permanent supersession means no earlier session can
affect active state. Therefore the bounded path and full-log fold are equivalent.

This is a required randomised property test, including duplicates, skewed timestamps, out-of-order
delivery, tied timestamps, mixed schema versions, and competing sessions. See
[`TESTING.md`](TESTING.md).

## Cross-device behaviour

Each user action appends locally and returns immediately. CloudKit later transports the immutable
event. Devices may temporarily have different prefixes of the log; after they receive the same set,
projection converges regardless of delivery order or duplication. No action waits for the network.

Only the authoring device writes an event to the synced store. If measurements justify a
WatchConnectivity fast path, receivers place the unchanged event in a separate local staging store.
The fold reads the union and deduplicates by `id`; when CloudKit delivers the canonical row, the
staging copy is pruned locally. WatchConnectivity is an optimisation and never a correctness
dependency. Details belong in [`ICLOUD_SYNC.md`](ICLOUD_SYNC.md).

Remaining seconds, elapsed seconds, phase snapshots, and per-second values are never synchronised.
A one-hour timer produces a handful of event rows rather than thousands of stale countdown writes.
On wake or relaunch, each device projects stored events and evaluates against an injected current
instant. UTC instants make timezone and daylight-saving changes irrelevant to timer arithmetic.

The system cannot prevent two offline devices from starting timers because CloudKit provides no
distributed lock. It instead guarantees deterministic convergence, permanent preservation of the
loser as history, and no silent resurrection.

## History strategy

History is a projection of the event log. Neither `TimerSession` nor `ActiveTimerState` nor a session
snapshot is stored or synchronised. A synchronised derived record would give two devices another
mutable representation of the same fact and reintroduce the property-level merge failure that the
event log removes.

History is paginated per session. For each session, use Q1 to supply its supersession boundary and Q2
to supply its events, then project and evaluate as required. Per-task totals query `.started` events
by immutable `relatedTaskID`, obtain their session IDs, and fold each bounded session. Superseded
elapsed time ends at the successor's start. `.stopped` work is retained; `.reset` work is discarded.

At expected volume, folding is cheap. If profiling later requires a cache or materialised index, it
must be local-only, invalidated on every log or staging change, and never synchronised. The synced
schema remains exactly `TaskRecord` and `TimerEventRecord`; see [`DATA_MODEL.md`](DATA_MODEL.md) and
ADR 013 in [`DECISIONS.md`](DECISIONS.md).

## Non-negotiable verification properties

Implementation is incomplete unless tests demonstrate idempotence, order independence, timeless
projection, bounded-query equivalence, arbitration permanence, the supersession cutoff, stale-command
rejection, mixed-version quarantine, and the always-stoppable guarantee. Stopping the winning session
must yield `.idle` and must never revive a superseded session. The detailed matrix is owned by
[`TESTING.md`](TESTING.md).
