# Testing Strategy

Swift Testing (`@Test`, `#expect`) throughout. XCTest only where tooling requires it (UI tests). **The domain packages hold the test mass**, because they hold all the risk and none of the I/O.

---

## Injected TimeSource Strategy

All time-dependent code receives time via a `protocol TimeSource: Sendable { var now: Date { get } }` (plan §10). The name is deliberately not `Clock` to avoid collision with Swift's standard library `Clock` type.

**Rule: NO test ever waits in real time.** Every test injects a fake `TimeSource` that returns deterministic values. A three-hour timer scenario is a sub-millisecond test. `TimerCalculator.evaluate(projection, at:)` and `TimerCalculator.elapsed(at:)` / `remaining(at:)` all take an explicit `at:` parameter. The view re-derives from timestamps every tick via `TimelineView` — a missed tick is invisible (plan §19).

This is what makes the entire timer feature exhaustively testable without flakiness, without sleep calls, and without timeout-based test infrastructure.

---

## TimerDomain — Highest Test Density

TimerDomain is the most important package and carries the highest test density because:

- It contains the fold (`TimerProjection.project`), which is the single point of correctness for the entire timer feature (plan §27, R-3).
- The fold is a pure function with no I/O, so every input sequence can be tested deterministically.
- TimerDomain holds all the project's technical risk: the state machine, derived expiry, arbitration, quarantine, and cross-device convergence properties.

### Required Properties

The following properties are not aspirational — they are mandatory, tested, and asserted as properties (not just unit cases):

#### Projection Timelessness

Projecting the same log under two wildly different `TimeSource`s must give byte-identical results. This is the test that guards the convergence invariant (plan §2.7, §10): the projection stage consults only the log, never the clock, never device identity, never arrival order. Any rule that depends on the receiving device would let two devices compute different projections from identical data — the one bug this architecture cannot tolerate.

#### Idempotence over Duplicated Events

CloudKit retries, re-syncs, and the WC fast-path can deliver the same logical event twice. `@Attribute(.unique)` is unavailable under CloudKit sync, so the fold dedupes by event `id` before folding. Folding a multiset must equal folding the set. This property is asserted with randomised logs containing deliberate duplicates (plan §10).

#### Order-Independence under Shuffling

Events are sorted deterministically before folding, so out-of-order delivery cannot change the outcome. Property test: shuffle the log, assert identical projection. Two orderings serve two different questions — Lamport order for intra-session causality, wall-clock order for inter-session arbitration — but the fold must produce the same result regardless of delivery order (plan §10, §20).

#### Bounded-Query Equivalence against a Full-Log Reference Implementation

Folding never scans the whole log in production. The bounded path uses two queries: Q1 (session-start index by `(kind, occurredAt, deviceID)`) and Q2 (all events for a target session). A reference implementation folds the entire log. Property-based randomised tests — including skewed timestamps, duplicates, out-of-order delivery and multiple competing sessions — assert that the bounded path and the reference fold produce identical state. If the optimisation ever diverges from the definition, the test fails (plan §28).

#### Arbitration Permanence

Stopping the winner must not resurrect a superseded session. Supersession is monotone and irreversible: every session earlier than the greatest `.started` is permanently terminated at the instant it was displaced. Displacing a session means it can never become active again, regardless of what happens to the sessions that displaced it. The test asserts that after stopping the winner, the state is `.idle` — no superseded session revives (plan §20).

#### Supersession Cutoff for Per-Task Totals

A session displaced at 14:10 contributes exactly its truncated elapsed time to per-task totals — never an open-ended interval. The cutoff instant lives in the successor's `.started` event, outside the superseded session's own events. Projection takes an explicit `supersededAt: Date?` boundary sourced from the Q1 start-index (plan §10, §28).

#### Always-Stoppable Guarantee

A future-skewed, quarantined, or otherwise pathological winner can always be terminated by `.stopped`, and the user is never locked out. The general invariant: no combination of clock skew, version skew, or partition can produce a timer that cannot be terminated. This is stated as a product guarantee and a required test (plan §10).

The escape hatch works because `.stopped` means "this session is over" regardless of whether it was running or paused, and its effect does not depend on the quarantined session's interior state. `.paused` and `.resumed` are withheld while quarantined because they obviously require knowing what the session was doing. `.reset` is withheld because it discards history, whereas `.stopped` retains it — a stale client that cannot interpret a session must never be handed the one command that erases it (plan §10).

#### Quarantine Behaviour and Lifting

Quarantine is scoped per session: a predicate over the session's events — *does any event here have an unknown `kind` or a `schemaVersion` above mine?* — evaluated on every projection. When the device updates to a build that understands the kind, the predicate goes false and quarantine lifts automatically. There is no quarantine flag to persist, sync, or migrate (plan §10).

Tests assert:
- Unknown event kinds cause session quarantine (read-only, with "update required" note).
- `.started` and `.stopped` remain authorable while quarantined (the escape hatch).
- `.paused`, `.resumed`, and `.reset` are withheld while quarantined.
- Quarantine lifts when the kind becomes known after an app update.
- `.started` is a permanently stable kind; schema evolution may add new kinds but may never add a second way to begin a session (plan §10).

#### Stale-Command Rejection

A `.resumed` arriving for an already-stopped session is a device that was behind; the fold drops it. `TimerTransition` returns `nil` for invalid input. Nothing throws; nothing crashes.

#### Additional Required Tests

- Every valid and invalid state-machine transition (plan §27).
- Remaining/elapsed across pause/resume cycles.
- Expiry evaluation including "expired while all devices asleep" (plan §27).
- Two offline devices starting simultaneously; the one with the later `(startedAt, deviceID)` wins.
- Randomised property tests covering duplicates, timestamp ties on `deviceID`, and mixed-version logs (plan §27).

---

## TaskDomain Tests

- Creation validation (title non-empty after trimming).
- Completion idempotence (`completedAt != nil` is the sole completion indicator — plan §9).
- Pool ↔ Today transitions via `scheduledDay`.
- `DayKey` behaviour across a timezone change and a DST boundary: a task scheduled for the 9th must not become the 8th after a flight, because `DayKey` is a calendar fact (`yyyy-MM-dd`), not a timestamp (plan §9).

---

## Persistence Tests (AppData)

- In-memory `ModelContainer` round-trips for `TaskRecord` and `TimerEventRecord`.
- Mapping fidelity: domain model ↔ SwiftData record, both directions.
- Migration from a fixture store.
- Staging-store pruning (WC events pruned when canonical row arrives via CloudKit — plan §16).
- Repository conformance run against the same suite as the fakes.

---

## Sync Tests

A `FakeTimerEventTransport` simulating:

- **Delay** — events arrive minutes after authoring.
- **Reordering** — events arrive out of order.
- **Duplication** — the same event observed twice after a forced resync or reinstall.
- **Partition** — two devices operating offline, then reconnecting.

Two simulated devices driven by the fake transport assert convergence — including the invariant that ignoring every WC message yields identical state. This proves F8 (cross-device timer observation and control) without hardware (plan §27, §16).

---

## Platform Tests

XCTest/XCUITest now covers high-risk app-level regressions directly:

- **iOS UI tests**: Today quick-add visibility, Pool multi-add visibility (regression for the "only last task appears" class), Timer preset/start/control-state/stop flow.
- **macOS UI tests**: Menu-bar panel segmented Today/Timer tabs (switch + default-to-Timer when
  active), quick-add visibility, circle-tap complete, title-tap details editor, Run button starts
  timer, Task Hub checkbox complete, "Open Tasks" window activation/opening, Settings opening from
  `MenuBarExtra`.
- **watchOS**: still manual for now; XCUITest coverage is intentionally deferred because watch UI automation remains limited and comparatively brittle for this app's current scope.
- Manual cross-device verification remains required for the real F8 sync walkthrough (plan §27).

---

## Pre-Completion Checklist

Every task must pass all of the following before it is considered complete (plan §27):

- [ ] Builds for all three platforms (macOS, iOS, watchOS) with zero warnings under strict concurrency.
- [ ] Domain tests pass (`xcrun swift test`).
- [ ] No timer arithmetic outside `TimerDomain`.
- [ ] No persistence type in a domain package.
- [ ] Dependency rules still hold (compiler-enforced).
- [ ] Affected `docs/` files updated in the same session.
- [ ] `memory.md` updated if project state changed.
- [ ] State plainly what changed, what was verified, and what was not.
