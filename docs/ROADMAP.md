# Roadmap

Milestones 0–9, dependency order, and rationale. Status is tracked here; `memory.md` tracks current state.

---

## Milestones

| M | Name | Contents | Tier | Status |
|---|---|---|---|---|
| 0 | Foundation | Workspace, packages, docs, CloudKit config, spike R-1 | MVP 0 | In Progress |
| 1 | TimerDomain | Events, Lamport, fold, state machine, calculator, arbitration, exhaustive tests. No UI, no persistence. | MVP 0 | Completed |
| 2 | TaskDomain | Model, DayKey, services, repository protocols, tests | MVP 0 | Completed |
| 3 | AppData (local) | SwiftData models, indexes, repositories, mapping, in-memory + migration tests. No CloudKit. | MVP 0 | Completed |
| 4 | Convergence proof | CloudKit mirroring on; throwaway two-device shells (Mac + iPhone) doing nothing but start/pause/resume; F8 proven on real hardware, including two-offline-starts, supersession permanence and duplicate delivery; schema promoted | MVP 0 | Not Started |
| 5 | macOS app | MenuBarExtra, Today, timer controls, quick-add, Pool search, preferences, AppFeature controllers, AppDesign v1 with adaptive surfaces | MVP 1 | Not Started |
| 6 | iOS app | Tabs, Today, Pool, Timer, task editing, timer presets, expiry notification | MVP 1 | Not Started |
| 7 | watchOS app | Standalone target, two screens, timer controls, R-1 re-measured; WC fast-path only if the numbers demand it | MVP 2 | Not Started |
| 8 | Reliability | Conflict scenarios end-to-end, long-offline recovery, edge-case sweep, history + per-task totals (F9) | MVP 2 | Not Started |
| 9 | Polish | Liquid Glass audit on 26+, material-fallback verification, layered app icon, accessibility pass | MVP 2 | Not Started |

---

## Dependency Order

```
0 Foundation → 1 TimerDomain → 2 TaskDomain → 3 AppData(local) → 4 Convergence proof
  → 5 macOS → 6 iOS → 7 watchOS → 8 Reliability → 9 Polish
```

Milestones 1 and 2 are independent and could run in parallel; 3 depends on both. Everything after 3 is strictly sequential (plan §33).

---

## Rationale for Ordering

### TimerDomain before TaskDomain (deliberately)

The instinct is to build the simpler domain first. That is wrong here. TimerDomain carries essentially all the project's technical risk: the fold, the state machine, derived expiry, arbitration. TaskDomain is a well-understood CRUD model with one interesting decision (`DayKey`). Building the risky thing first means that if event-sourcing proves disproportionate (R-4), we discover it in week two with nothing built on top — not in month three with three UIs depending on it (plan §33).

### Local persistence before sync, but sync before any real UI

Milestone 3 gives a working local store, so sync becomes a change to one layer with a baseline to compare against. Milestone 4 then proves convergence on disposable shells *before* the macOS app is built on it. The two riskiest things in the project — the fold, and cross-device convergence — are both settled while nothing depends on them (plan §33).

### macOS before iOS

It is the primary surface and the most constrained one. A design that fits a menu-bar panel will expand to a phone; a design built for a phone will not compress (plan §33).

### watchOS last

Least surface area, depends on sync already being proven, and its one open question (R-1: CloudKit propagation latency to a sleeping watch) is best answered against a real two-device system already running (plan §33).

### Milestone 4 is the critical scheduling decision

An earlier ordering built the entire macOS app before any two-device synchronisation existed, deferring the project's second-largest risk behind its largest deliverable. The shells built in Milestone 4 are deliberately disposable — two buttons and a label — because their job is to prove convergence, not to look like anything. If the conflict model is wrong, it is found here, with no UI depending on it (plan §32).

---

## Milestone Details

### M0 — Foundation (MVP 0)

Create `TaskTracker.xcworkspace` and `TaskTracker.xcodeproj` with three app targets (watchOS embedded in iOS, running independently), five local SPM packages, Swift 6.2 strict concurrency everywhere, deployment targets iOS 18 / macOS 15 / watchOS 11, bundle prefix `com.diwan.TaskTracker`. Create package manifests encoding the dependency rules — empty targets, no implementation. Write `CLAUDE.md`, `AGENTS.md`, `memory.md`, and all `docs/` files including 14 ADRs. Configure CloudKit container `iCloud.com.diwan.TaskTracker`. Run spike R-1 measuring latency, duplicate delivery, and concurrent insert behaviour on a floor-vs-current device matrix including watchOS 11 on real hardware. Verify: all three targets build clean with zero warnings; the dependency graph is compiler-enforced (plan §31).

### M1 — TimerDomain (MVP 0)

The most important package. Events, Lamport clock, fold (projection + evaluation), state machine, calculator, arbitration, quarantine, forward compatibility. Exhaustive tests covering all required properties (see `TESTING.md`). No UI, no persistence — pure domain only.

### M2 — TaskDomain (MVP 0)

Pure value types: `Task`, `TaskStatus`, `DayKey`. Task service (create/edit/complete/schedule rules). Repository protocol. `DayKey` as ISO `yyyy-MM-dd` string key, stable under timezone changes and DST. Tests for creation validation, completion idempotence, Pool ↔ Today transitions, DayKey behaviour across timezone/DST boundaries.

### M3 — AppData Local (MVP 0)

SwiftData models (`TaskRecord`, `TimerEventRecord`), indexes, repository implementations, mapping between domain models and records. In-memory `ModelContainer` tests. Migration from fixture store. Staging-store pruning. No CloudKit yet — local-only baseline.

### M4 — Convergence Proof (MVP 0)

CloudKit mirroring turned on. Throwaway two-device shells (Mac + iPhone) doing nothing but start/pause/resume. F8 proven on real hardware: two-offline-starts, supersession permanence, duplicate delivery. Schema promoted from development to production. Minimum-OS device matrix tested. This milestone validates the two riskiest elements — the fold and cross-device convergence — before any real UI depends on them (plan §32).

### M5 — macOS App (MVP 1)

`MenuBarExtra(.window)` as primary surface. Today list, timer controls, quick-add, Pool search, preferences. `AppFeature` controllers (`ActiveTimerController`, `TodayController`, `PoolController`) and use cases. `AppDesign` v1 with adaptive surfaces (Liquid Glass conditional on 26+, material fallback below). Menu-bar label: SF Symbol when idle, monospaced-digit countdown when active.

### M6 — iOS App (MVP 1)

`TabView` with `.tabViewStyle(.sidebarAdaptable)` (iOS 18 floor). Tabs: Today · Pool · Timer · Settings. Timer presets (15/25/30/45/60). Expiry notification (local, scheduled at `.started`, cancelled on pause/stop/reset, rescheduled on resume — plan §28). Task editing as a sheet. Pool→Today via swipe action and context menu.

### M7 — watchOS App (MVP 2)

Standalone watchOS app (`WKRunsIndependentlyOfCompanionApp`). Two screens: Active Timer (large monospaced countdown, primary control, secondary controls behind swipe) and Today (tap to complete, long-press to start timer). R-1 re-measured against the real two-device system. WC fast-path added only if the numbers demand it — decided with data, not speculation (plan §24).

### M8 — Reliability (MVP 2)

End-to-end conflict scenarios. Long-offline recovery. Edge-case sweep (plan §28 table). History and per-task totals (F9). The bounded-query path verified against the reference fold with production-scale logs.

### M9 — Polish (MVP 2)

Liquid Glass audit on 26+. Material-fallback verification on the floor (iOS 18 / macOS 15 / watchOS 11). Layered app icon (Icon Composer, three layers, all appearance variants, circular watchOS mask). Accessibility pass: Dynamic Type, VoiceOver labels, Reduce Transparency, Increase Contrast, Reduce Motion. Both appearances laid out and reviewed — the floor build is a first-class appearance, not a degraded mode (plan §26).
