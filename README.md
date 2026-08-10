# TaskTracker

TaskTracker is a **local-first personal task manager** with an optional **device-independent focus timer** for **macOS, iOS, and watchOS**.

- **No backend** and **no third-party dependencies**
- **SwiftData + iCloud (CloudKit private DB) mirroring**
- Timer correctness is achieved with an **append-only event log** (not a mutable “active timer” record)

Project status and milestone tracking live in `docs/ROADMAP.md` and `memory.md`.

---

## What you get (product)

- **Pool**: a durable reservoir of unscheduled ideas (`scheduledDay == nil && completedAt == nil`)
- **Today**: a focused list built by assigning Pool items to a specific day (`scheduledDay != nil`)
- **Focus timer**: start/pause/resume/stop/reset, synced as immutable events across devices

Terminology and user flows are defined in `docs/PRODUCT.md`.

---

## Architecture (how it works)

### Packages and dependency rules

This repo is intentionally split into five local SwiftPM packages plus three app targets.

```
Packages/TimerDomain   pure domain (Foundation only)
Packages/TaskDomain    pure domain (Foundation only)
Packages/AppData       SwiftData + CloudKit + repository implementations
Packages/AppFeature    @Observable controllers + use cases
Packages/AppDesign     SwiftUI-only design system + appearance seam

Apps/macOS  Apps/iOS  Apps/watchOS   (composition roots + views)
```

**Non‑negotiable dependency direction** (compiler-enforced; see `docs/ARCHITECTURE.md`):

```
TaskDomain   TimerDomain   (pure)
      ↑           ↑
      └─────┬─────┘
         AppData            (SwiftData / CloudKit)
            ↑
         AppFeature         (@Observable)
            ↑
  macOS / iOS / watchOS  ←  AppDesign (SwiftUI only)
```

Key rules:
- Domain packages (`TaskDomain`, `TimerDomain`) import **only** the standard library + `Foundation`.
- App targets contain **no business rules** and **no timer arithmetic**.
- `TimerDomain` references a task only as `UUID?` (no import of `TaskDomain`).

### Task model

`TaskDomain` uses a small value model:
- Completion is **derived**: `isCompleted = completedAt != nil` (never a parallel boolean).
- “Pool” is a **query**, not a container:
  - Pool: `scheduledDay == nil && completedAt == nil`
  - Today: `scheduledDay == DayKey("yyyy-MM-dd")`

`DayKey` is an ISO day string (e.g. `"2026-08-09"`) so a task scheduled for “the 9th” does not shift after a timezone/DST change. See `docs/TASK_ARCHITECTURE.md`.

### Timer model (the important part)

The timer is **shared logical state**, not a running process. Devices sync **timestamps and user actions**, never per‑second values.

**Timer truth** is an **append-only log** of immutable `TimerEvent` rows:

```
[TimerEvent] --project (timeless)--> SessionProjection --evaluate(at:)--> ActiveTimerState
```

- `project(...)` is **timeless**: depends only on the log (no clock, no device identity, no arrival order).
- `evaluate(at:)` is **time-dependent and pure**: computes elapsed/remaining and derives expiry, but **writes nothing**.
- Concurrent starts resolve deterministically via **arbitration**; supersession is permanent.

Full timer architecture is in `docs/TIMER_ARCHITECTURE.md`.

### Local-first + iCloud sync

All user actions are **local writes first**:

```
User action → AppFeature → AppData repository → SwiftData write (local)
                                        ⋮
                         CloudKit mirroring uploads later (background)
```

Sync details and invariants are documented in `docs/ICLOUD_SYNC.md`.

---

## Data model (SwiftData)

The synced schema is intentionally frozen to **two entities only** (see `docs/DATA_MODEL.md`):
- `TaskRecord`
- `TimerEventRecord`

No unique constraints and no CloudKit relationships are used; associations are UUID fields resolved in `AppData`.

---

## Building and testing

### Important (toolchain)

This machine has a stale Swift toolchain that can shadow Xcode’s Swift. **Always build with `xcrun`** (see `AGENTS.md`):

```bash
xcrun swift test --package-path Packages/TimerDomain
xcrun swift test --package-path Packages/TaskDomain
xcrun swift test --package-path Packages/AppData
```

### Running the app

Open `TaskTracker.xcodeproj` in Xcode and run one of:
- `TaskTracker-macOS`
- `TaskTracker-iOS`
- `TaskTracker-watchOS`

UI/features are delivered by milestones (see below); early milestones may run as skeleton apps.

---

## Milestones

The implementation order is deliberate (risk-first). See `docs/ROADMAP.md` and `plans/plan01.md`.

Current sequence:

```
0 Foundation → 1 TimerDomain → 2 TaskDomain → 3 AppData(local) → 4 Convergence proof
  → 5 macOS → 6 iOS → 7 watchOS → 8 Reliability → 9 Polish
```

---

## Contributing / repo rules

Read these first:
- `AGENTS.md` (rules, dependency constraints, verification checklist)
- `docs/ARCHITECTURE.md` (what goes where)
- `docs/TESTING.md` (what must be tested)

