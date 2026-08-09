# Architecture

## Package Overview

Five local SPM packages, three app targets. The dependency graph is enforced by package manifests — a deliberate `import TimerDomain` inside `TaskDomain` (or any other violation) must fail the build (plan §8).

```
TaskTracker.xcworkspace
├── Packages/
│   ├── TimerDomain     — pure. zero dependencies.
│   ├── TaskDomain      — pure. zero dependencies.
│   ├── AppData         — SwiftData + CloudKit + repository implementations
│   ├── AppFeature      — @Observable controllers + use cases
│   └── AppDesign       — SwiftUI design system, tokens, adaptive surfaces
├── Apps/  macOS/  iOS/  watchOS/
├── docs/   plans/
├── CLAUDE.md  AGENTS.md  memory.md
```

---

## Why Five Packages

### Why `TaskDomain` and `TimerDomain` are separate

Task and Timer are independent domains. The relationship between them is genuinely optional in both directions, and the cardinality is one-task-to-many-sessions. A naive model makes Timer a child of Task, which forecloses general timers, multi-session history, and independent evolution (plan §3).

`TimerDomain` references a task only as an opaque `UUID?`. Neither package imports the other. `TaskDomain` has no knowledge that timers exist. This is enforced at the compiler level — the domain packages import only the standard library and `Foundation` (plan §8).

Alternatives rejected:
- `Task.activeTimer` — makes Timer a lifecycle-dependent child, blocks history, pollutes every task record with timer columns (plan §3).
- A `TaskTimerLink` join entity — a relationship table for a relationship already expressible as a nullable identifier (plan §3).
- One package with two namespaces — a namespace is not a boundary; the compiler must enforce this or it will erode (plan §3).

### Why `AppFeature` exists

Cross-platform `@Observable` presentation controllers (`ActiveTimerController`, `TodayController`, `PoolController`) and the use cases they call. Without it, "start a timer for task X" — validation, repository call, optimistic local update, error surfacing — is written three times (plan §7).

The anti-drift rule: `AppFeature` may contain only `@Observable` types and use cases. Reusable and stateless goes to a domain package. Visual goes to `AppDesign`. Reviewed at every milestone (plan §7).

App targets depend on `AppFeature` + `AppDesign` and contain only views, scenes, and platform adapters.

### Why `SharedCore` was rejected

The only genuine overlap is a time abstraction (~4 lines) and a couple of error protocols. Duplicating a four-line protocol is strictly cheaper than a package that couples two domains §3 exists to separate (plan §7).

Revisit only if three or more distinct abstractions are duplicated.

### Why `AppDesign` is separate

`AppDesign` imports SwiftUI only — never a domain, never `AppData`. Components take plain parameters, not domain models. It owns the design system, tokens, adaptive surfaces, and the component-level compatibility seam for Liquid Glass (see `DESIGN_SYSTEM.md`).

---

## Dependency Graph and Compiler-Enforced Invariants

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
- `AppDesign` imports SwiftUI only — never a domain, never `AppData`.
- App targets contain no business rules and no timer arithmetic.

---

## App Targets

Three independent executables: macOS, iOS, watchOS. Each is a composition root — it constructs its own `AppEnvironment` at `@main` and injects it into the controllers it receives from `AppFeature` (plan §7).

Composition roots live in the app targets, not in `AppFeature`. Three independent executables cannot share one composition root: different entry points, different platform adapters (menu-bar scene vs. `WindowGroup` vs. watch scene), different lifecycles. `AppFeature` ships the *ingredients*: controller types with explicit initialiser dependencies, plus an `AppEnvironment` value bundling the repository set (plan §7).

- **macOS** (`plan §21`, revised 2026-08-09): `MenuBarExtra(.window)` remains the primary surface — `LSUIElement` accessory activation policy, no Dock icon. It opens a singleton auxiliary `Window` (not `WindowGroup` — the task hub is one window representing global app state, see `docs/ROADMAP.md` M5) for the full task hub — managing and editing tasks beyond what the menu-bar panel fits. The app is still accessory-activated; the window is opened on demand, not shown at launch.
- **iOS** (`plan §22`): `TabView` with `.tabViewStyle(.sidebarAdaptable)` (floor is iOS 17 — see ADR 014 Revision 2). Tabs: Today · Pool · Timer · Settings.
- **watchOS** (`plan §23`): Standalone watchOS app (`WKRunsIndependentlyOfCompanionApp`), embedded in the iOS app for a single App Store record but functional without the phone. Two screens, no deeper hierarchy.

---

## Layers

### Domain Layer (TaskDomain, TimerDomain)

Pure `Sendable` value types and free functions. No actors, no async — the fold is synchronous and deterministic; making it async would buy nothing and cost testability. No persistence vocabulary. No I/O. The fold, state machine, calculator, and arbitration are all pure functions (plan §25).

### Persistence Layer (AppData)

`@ModelActor` for background SwiftData work; repositories actor-isolated; boundaries exchange `Sendable` value types, never `PersistentModel` instances. `AppData` owns all CloudKit contact — `AppFeature` and app targets never import CloudKit (plan §16, §25).

### Application Layer (AppFeature)

`@MainActor @Observable` controllers; `async` methods awaiting repositories. This is an application layer, not a folder. Controllers in `AppData` were rejected because they mix presentation state with persistence. Controllers duplicated per app were rejected because they violate the anti-fragmentation rule (plan §7).

### Presentation Layer (App targets + AppDesign)

`@MainActor` throughout. App targets contain only views, scenes, and platform adapters. `AppDesign` provides the SwiftUI design system: tokens, typography, SF Symbols, adaptive surfaces, and the component-level Liquid Glass compatibility seam (see `DESIGN_SYSTEM.md`).

---

## Data Flow

```
User action → AppFeature controller → repository (AppData)
           → SwiftData write (local, immediate)
           → UI updates from local store
           ⋮
           → CloudKit mirroring uploads when able (background, invisible)
```

No user-facing operation ever awaits the network. The UI reads only the local store. Sync is background. Offline is the normal case, not an error (plan §15).

---

## Concurrency Boundaries

Swift 6 language mode, strict concurrency, from the first commit (plan §25).

| Layer | Model |
|---|---|
| `TaskDomain`, `TimerDomain` | Pure `Sendable` value types and free functions. No actors, no async. |
| `AppData` | `@ModelActor` for background SwiftData work; repositories actor-isolated. |
| `AppFeature` | `@MainActor @Observable` controllers; `async` methods awaiting repositories. |
| App targets | `@MainActor` throughout. |

**Hard rule: SwiftData model objects never cross an isolation boundary.** Repositories map records to domain value types at the edge, both directions. This is the single most effective defence against the class of Swift 6 errors that make SwiftData painful, and it keeps the domains persistence-ignorant — one rule, two benefits (plan §25).

---

## TaskDomain and TimerDomain Integration

The two domains integrate **only in `AppData`**. `AppData` is where the `UUID?` reference from `TimerEvent.relatedTaskID` is resolved to a `Task` for display, where the staging store is managed, and where the repository implementations live (plan §11, §14).

Neither domain imports the other, and neither has knowledge of the other's models. A deleted task leaves sessions with a dangling ID; the join in `AppData` resolves it to "Deleted task" for display. Enforcing referential integrity would require a real CloudKit relationship, which the persistence architecture rules out (plan §11).

---

## Forward Compatibility

`TimerEvent.kind` is persisted as a `String`, not an enum raw value, so an unknown kind deserialises rather than failing. `schemaVersion` accompanies every event. An event with an unrecognised `kind` or a newer `schemaVersion` is skipped by the projection and never deleted from the store. An older build must not destroy data it does not understand (plan §10).

`.started` is a permanently stable kind. Schema evolution may add new event kinds, but may never add a second way to begin a session. This guarantees that arbitration is fully computable by any client, of any age, without interpreting a single unknown kind (plan §10).

---

## Cross-References

- `TASK_ARCHITECTURE.md` — TaskDomain model, DayKey, Today/Pool semantics, lifecycle, invariants
- `TIMER_ARCHITECTURE.md` — Event log, Lamport mechanics, fold, state machine, derived expiry, arbitration, quarantine, cross-device behaviour
- `DATA_MODEL.md` — Persistence models, CloudKit constraints, indexes, staging store, migrations
- `ICLOUD_SYNC.md` — Container setup, local-first flows, dual ingress, conflicts, watch sync
- `DESIGN_SYSTEM.md` — Adaptive surfaces, Liquid Glass rules, tokens, typography, accessibility
- `TESTING.md` — Per-layer strategy, injected TimeSource, pre-completion checks
- `ROADMAP.md` — Milestones, dependency order, live status
- `PRODUCT.md` — Vision, user, terminology, workflows, MVP tiers
