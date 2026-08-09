# Product Vision

TaskTracker is a lightweight personal productivity utility for one user across their own Apple devices. It pairs a durable pool of tasks and ideas with a focused Today list and an optional, device-independent focus timer that is the same timer on every device.

macOS is the primary daily surface and lives in the menu bar. iOS is the management surface. watchOS is a glance-and-control surface. Local-first. Fully usable offline. iCloud is a synchroniser, not a dependency.

---

## Target User

One person — the app owner — using their own Apple devices (macOS, iOS, watchOS). There is no collaboration, no shared data, no accounts, and no multi-user consideration. Every design decision assumes a single person with a phone, a Mac, and optionally a watch.

---

## Terminology

### Pool

The durable reservoir of tasks and ideas with no date attached. The Pool is a query over data — `scheduledDay == nil && completedAt == nil` — not a container.

**Why "Pool" over "Inbox" or "Backlog" (plan §9):** An Inbox is a triage queue that must be processed to zero, and a never-emptied Inbox generates guilt. A Backlog implies prioritised committed work. The described object is neither — it is a durable reservoir of ideas that is *supposed* to stay full and be drawn from repeatedly. "Pool" is the user's own word and the only one whose connotation matches the behaviour.

### Today

A focused list, assembled by pulling from the Pool or creating directly. Today assignment is expressed as `scheduledDay: DayKey?` on `Task`. `DayKey` wraps an ISO `yyyy-MM-dd` string, resolved in the device's current calendar at the moment of assignment — a calendar fact, not a timestamp, so it is stable under timezone changes and DST (plan §9).

### TimerSession

One focus run, past or present. Created by folding a `TimerEvent` log. Cardinality: many (permanent history). A session may optionally reference a task via `relatedTaskID: UUID?`, set once on `.started` and immutable thereafter (plan §11).

### ActiveTimerState

The single logically-active timer, globally. Cardinality: exactly zero or one. Derived by arbitration over all session starts, then projected and evaluated at the current instant. Never persisted, never synchronised — every device recomputes it locally from the synced event log (plan §12).

```swift
enum ActiveTimerState {
    case idle
    case active(TimerSession, TimerPhase)
    case completed(TimerSession, CompletionReason)
}
```

### General vs Task-Associated Timer

A timer may or may not reference a task. A general timer (no task) records a focus duration. A task-associated timer links to a Today task at start time via `relatedTaskID: UUID?`. The relationship is optional in both directions — TimerDomain references a task only as an opaque UUID; TaskDomain has no knowledge that timers exist (plan §3).

---

## Primary User Flows

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

---

## MVP Tiers

The proposed MVP is three platforms × two domains × sync × Liquid Glass. Shipping it as one milestone means the riskiest element (cross-device timer convergence) is validated last, after every UI has been built on assumptions it might invalidate. Split into three (plan §5):

### MVP 0 — Foundations Proven

TimerDomain + TaskDomain + local SwiftData + CloudKit convergence proven on disposable two-device shells. No real UI.

Contents: workspace, packages, documentation, CloudKit configuration, spike R-1 (latency, duplicate delivery, concurrent insert), TimerDomain with exhaustive tests, TaskDomain, AppData (local), convergence proof on throwaway Mac + iPhone shells.

### MVP 1 — "It Works on My Mac and My iPhone"

macOS menu bar app, iOS app, offline behaviour, timer presets, expiry notification. First genuinely usable release.

Contents: `MenuBarExtra` macOS app with Today, timer controls, quick-add, Pool search, preferences; iOS tabbed app with Today, Pool, Timer, Settings; `AppFeature` controllers; `AppDesign` v1 with adaptive surfaces.

### MVP 2 — "It Works Everywhere and Looks Right"

watchOS app, latency hardening, history/per-task totals (F9), Liquid Glass polish on 26+, layered app icon, accessibility pass.

Contents: standalone watchOS app (two screens, timer controls); reliability sweep (conflict scenarios, long-offline recovery, edge cases); per-task totals; Liquid Glass audit on 26+; material-fallback verification; layered app icon; accessibility pass.

**What / why / alternatives (plan §5):** Vertical slices over horizontal layers, because a horizontal plan defers integration risk to the end. One big MVP was rejected because timer-convergence bugs found in month four would force UI rework across three platforms.

---

## Out of Scope

Explicitly excluded from this project:

- Web platform
- Android platform
- Collaboration or shared data
- User accounts or authentication
- Firebase, Supabase, or custom backends (single-user private data; CloudKit is free, needs no auth code, and no backend means no server to operate — plan §6)
- AI features
- Analytics
- Kanban boards
- Subtasks
- Recurring tasks
- Calendar integration
- Complex notifications (one local notification for timer expiry while backgrounded is in scope — plan §28)
- Compaction of the event log (deferred to its own post-MVP ADR — plan §28)
- Complications, Smart Stack widgets, watch-face integration, haptic expiry alerts, background refresh tuning on watchOS (deferred — plan §23)

---

## UX Principles

1. **Local-first.** Every user action commits locally and returns immediately. Sync is background (plan §15). No user-facing operation ever awaits the network. The UI reads only the local store. Offline is the normal case, not an error.

2. **Speed over decoration.** The menu bar interaction budget is a fraction of a second. The UI must not imply that CloudKit is realtime (plan §2, §15).

3. **Native per platform.** Shared domain, shared design tokens — not shared layouts. macOS is dense and keyboard-first; iOS is touch-first and navigational; watchOS prioritises glanceability with minimal transparency and high contrast (plan §2, §26).

4. **Eventually consistent remotely.** iCloud is not realtime. Two devices with skewed clocks may momentarily disagree about a just-expired timer — that is not a convergence failure, because nothing is persisted from an evaluation. The disagreement resolves itself the instant either clock advances past the deadline (plan §10).

5. **Timestamps are truth.** Never synchronise a decrementing number. A 60-minute session with two pauses produces five records for the entire hour, versus 3,600 writes if remaining seconds were mirrored (plan §17).

6. **No silent data loss.** Conflicts resolve deterministically, and the loser is preserved. A superseded session is retained in the log with its real elapsed time and task link (plan §2, §20).

7. **Convergence is a property, not a hope.** Every device folding the same log must reach the same projection. Any rule that depends on the receiving device's identity, arrival order, or clock is forbidden at projection time. Time enters only at evaluation, which writes nothing (plan §2, §10).
