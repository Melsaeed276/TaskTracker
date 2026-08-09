# AGENTS.md — rules for any coding agent working in this repository

Applies to every agent (Claude, Codex, Cursor, opencode) and every human.

**Source of truth:** `plans/plan01.md` (approved) and `docs/`. If your instinct conflicts with them,
the documents win. If you believe a document is wrong, say so and stop — do not silently deviate.

## Repository structure

```
Packages/TimerDomain   pure domain. zero dependencies.
Packages/TaskDomain    pure domain. zero dependencies.
Packages/AppData       SwiftData + CloudKit + repository implementations
Packages/AppFeature    @Observable controllers + use cases
Packages/AppDesign     SwiftUI design system + appearance compatibility seam
Apps/macOS Apps/iOS Apps/watchOS   views, scenes, platform adapters, composition roots
docs/                  durable architecture and product knowledge
plans/plan01.md        the approved plan
memory.md              current project state
```

## Dependency rules — compiler-enforced, non-negotiable

```
TaskDomain   TimerDomain      (import only Swift stdlib + Foundation)
      ↑           ↑
      └─────┬─────┘
         AppData                (SwiftData, CloudKit)
            ↑
        AppFeature              (@Observable, use cases)
            ↑
   macOS   iOS   watchOS   ←── AppDesign (SwiftUI only)
```

- `TaskDomain` and `TimerDomain` must NOT import: each other, SwiftUI, SwiftData, CloudKit,
  WatchConnectivity, or any app target.
- `AppData` must not import `AppFeature`, `AppDesign`, or any app target.
- `AppDesign` imports SwiftUI only. Its components take plain values, never domain models.
- App targets contain no business rules and no timer arithmetic.

## Environment

A stale Swift 5.0.3 toolchain shadows Xcode's on this machine. **Always build via `xcrun`**
(`xcrun swift build`, `xcrun swift test`) or `xcodebuild`. A bare `swift build` will fail with
duplicate-Foundation-class errors. Toolchain is Swift 6.3.3, Xcode 26.6.

Deployment floor: **macOS 15 Sequoia · iOS 18 · watchOS 11**. SDKs are 26.x, so every Liquid Glass
API needs an availability gate.

## Agents must NOT

- Put timer calculations inside SwiftUI views. All arithmetic lives in `TimerDomain`.
- Synchronise remaining seconds, elapsed seconds, or any per-second value. Ever.
- Duplicate Task or Timer business logic across app targets — that is what `AppFeature` is for.
- Make `TimerDomain` depend on `TaskDomain` to reference a task. Use `UUID?`.
- Add persistence, SwiftUI, or CloudKit APIs to a domain package.
- Add a CloudKit relationship, a `@Attribute(.unique)`, or a non-optional property without a default
  to a synced model. All three are forbidden by the CloudKit contract.
- Store derived state in the synced store. History is projected from the log.
- Change the synchronisation strategy, add a backend, or add a third-party dependency.
- Ignore or "improve upon" the architecture documents.

## Timer rules (the highest-risk area — read `docs/TIMER_ARCHITECTURE.md` first)

- The event log is append-only. Events are never mutated or deleted.
- `project(events, supersededAt:)` is **timeless**: no clock, no device identity, no arrival order.
- `evaluate(projection, at:)` is time-dependent, pure, and **persists nothing**.
- Expiry is derived by evaluation, never emitted as an event.
- Lamport ordering is for causality *within* a session. Wall-clock `(startedAt, deviceID)` arbitrates
  *between* sessions. Never swap them.
- Supersession is permanent. Stopping the active session yields `.idle`, never a revived session.
- The user can always stop whatever timer is active. Do not add a code path that breaks this.

## Task rules

- Completion is `completedAt != nil`. Never add a parallel boolean.
- `DayKey` is ISO `yyyy-MM-dd` in the device's current calendar. Never a `Date`.
- The Pool is a query (`scheduledDay == nil && completedAt == nil`), not a container.

## Testing requirements

- Swift Testing (`@Test`, `#expect`).
- `TimerDomain` carries the highest test density. Its required properties are listed in
  `docs/TESTING.md` — timelessness, idempotence, order-independence, bounded-query equivalence,
  arbitration permanence, supersession cutoff, always-stoppable, quarantine.
- Time is always injected via `TimeSource`. **No test may wait in real time.**

## Completion checklist — every task

1. Builds for macOS, iOS and watchOS with zero warnings under Swift 6 strict concurrency.
2. Relevant tests written and passing (`xcrun swift test`).
3. No timer arithmetic outside `TimerDomain`; no persistence type inside a domain package.
4. Dependency rules still hold.
5. Affected `docs/` updated **in the same session**.
6. `memory.md` updated if project state changed.
7. State plainly what changed, what was verified, and what was not.
