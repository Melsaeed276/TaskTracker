# Project State

TaskTracker — personal task manager + device-independent focus timer for macOS, iOS, watchOS.
Local-first, SwiftData + CloudKit private mirroring, no backend, zero third-party dependencies.

Plan approved 2026-08-09 after five Codex review rounds: `plans/plan01.md` (Draft 6).

# Current Milestone

**Milestone 0 — Foundation.** In progress.

Done and verified:
- Five SPM packages scaffolded, all building clean (Swift 6 language mode).
- Dependency rules compiler-enforced and *verified by probe*: `import TaskDomain` inside
  `TimerDomain` fails with `no such module`. Probe is re-run at every milestone gate.
- `git init`, `.gitignore`, `CLAUDE.md`, `AGENTS.md`, `memory.md`.
- XcodeGen `project.yml` + three app-target skeletons. **macOS builds.**
- All ten `docs/` files written (Codex: TIMER_ARCHITECTURE, DECISIONS with 14 ADRs;
  opencode: the other eight) and spot-checked against the plan.

Outstanding:
- CloudKit container + entitlements — **user is handling the Team ID.**
- **Spike R-1** — blocked on the deployment-floor decision below.
- watchOS/iOS targets cannot build until the watchOS platform is installed (see Known Issues).

# Completed Work

- Milestone 0 scaffolding only (foundation).
- **Milestone 1 — TimerDomain implemented and verified** (`xcrun swift test --package-path Packages/TimerDomain`).
- **Milestone 2 — TaskDomain implemented and verified** (`xcrun swift test --package-path Packages/TaskDomain`).

# Active Work

Milestone 0 documentation.

# Architecture Decisions Made

All 14 ADRs are specified in `plans/plan01.md` §30 and written up in `docs/DECISIONS.md`.
The two that explain most of the codebase:

- **Task and Timer are independent domain packages**; a timer references a task only as `UUID?`.
- **Timer state is an append-only event log**, because SwiftData+CloudKit has no custom merge hook
  and property-level merging can produce timer states that never existed. Immutable events never
  merge. This drives the projection/evaluation split, arbitration, and the absence of stored
  derived state.

# Important Constraints

- Deployment floor **macOS 15 Sequoia · iOS 18 · watchOS 11**; SDKs are 26.x, so every Liquid Glass
  API needs an availability gate and **every platform ships two appearances**.
- Synced schema is frozen at **two entities**: `TaskRecord`, `TimerEventRecord`. No relationships,
  no unique attributes, all properties optional or defaulted. A separate non-mirrored container
  holds the WatchConnectivity staging store.
- Never synchronise a per-second value.
- `project()` is timeless; `evaluate(at:)` is time-dependent and persists nothing.
- Bundle prefix `com.diwan.TaskTracker`; container `iCloud.com.diwan.TaskTracker`.

# Known Issues

- **A stale Swift 5.0.3 toolchain shadows Xcode's.** A bare `swift build` fails with duplicate
  Foundation classes. Always use `xcrun`. Toolchain in use: Swift 6.3.3 / Xcode 26.6.
- **Cursor CLI is not authenticated** (`cursor-agent login` required). Its Milestone 0 docs were
  reassigned to opencode.

# Open Questions

**The deployment floor conflicts with the available hardware — awaiting a decision.**

Paired devices found: Apple Watch Series 6 on **watchOS 26.0**, iPhone 13 mini, iPhone 11.
There is **no watchOS 11 device**, so the approved 18/15/11 floor would ship a watchOS fallback
appearance that was never verified on hardware — paying the dual-appearance cost (R-6) while
carrying untested code. Options: (1) raise the floor to 26 everywhere and delete the compatibility
seam entirely; (2) keep the floor and accept simulator-only verification on watchOS; (3) keep the
floor on macOS/iOS where it is testable, and make watchOS 26+.

This decision affects §26, R-6, ADR 014, and `docs/DESIGN_SYSTEM.md`. **Docs currently reflect the
approved 18/15/11 floor** and must be revised if the floor changes.

# Next Recommended Steps

1. Finish `docs/`; verify consistency against `plans/plan01.md`.
2. `project.yml` + three app targets; confirm all three build.
3. CloudKit container + entitlements.
4. Run spike R-1 and record results in `docs/ICLOUD_SYNC.md`.
5. Milestone 0 verification.
6. Begin **Milestone 3 — AppData (local)**.

# Recent Changes

2026-08-09 — Fixed Xcode Issue Navigator spam about *Tests source paths: XcodeGen's local-package
folder refs were confusing SourceKit. `postGenCommand` now strips them
(`scripts/strip-local-package-folder-refs.py`). Layout was already correct; CLI tests were fine.
2026-08-09 — Plan approved. Milestone 0 started: packages, boundary probe, root docs.
