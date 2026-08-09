# Project State

TaskTracker — personal task manager + device-independent focus timer for macOS, iOS, watchOS.
Local-first, SwiftData + CloudKit private mirroring, no backend, zero third-party dependencies.

Plan approved 2026-08-09 after five Codex review rounds: `plans/plan01.md` (Draft 6).

# Current Milestone

**Milestone 0 — Foundation.** Complete and verified (see Completed Work).

**Milestone 4 — Convergence proof.** Construction half complete and verified; hardware/CloudKit
half still blocked.

Done and verified this session (all three schemes build zero-warning, all 25 package tests pass,
dependency-rule probe intact):
- `AppDataModelContainer.makeSynced()` — CloudKit-mirrored container factory
  (`ModelConfiguration(cloudKitDatabase: .private(cloudKitContainerIdentifier))`). Verified
  `TaskRecord`/`TimerEventRecord` satisfy the CloudKit contract (no relationships, no unique
  attributes, all properties optional/defaulted) before adding it.
- Convergence-proof tests (`Packages/AppData/Tests/AppDataTests/ConvergenceProofTests.swift`):
  two-offline-starts merge-order-independence, supersession permanence across two containers +
  a stop on the winner, duplicate-event-id idempotence. Reference oracle for the later real-hardware
  run.
- `ActiveTimerController` (`AppFeature`) — start/pause/resume/stop against `TimerEventRepository`,
  state derived via `TimerEngine.evaluateActiveTimer`, Lamport clock maintained, no stored derived
  state, no timer arithmetic in views.
- Throwaway Mac (`MenuBarExtra`) and iPhone shells wired to the controller via
  `AppDataModelContainer.makeLocalInMemory()` — three buttons + state label, nothing more, per
  roadmap's "two buttons and a label" scope.
- All five package manifests bumped to `swift-tools-version: 6.2` and
  `platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26)]` to match the ADR 014 floor revision.
- `xcodebuild -downloadPlatform watchOS` completed; watchOS 26.5 simulator runtime now installed.
  `TaskTracker-iOS` (which embeds the watch app) and `TaskTracker-watchOS` both build clean.

Still outstanding — needs a real Apple Developer Team ID (user chose to skip signing for now):
- **CloudKit container + entitlements.** A cached codesign identity (`T96KAT2Q28`) was mistakenly
  treated as a valid signed-in account earlier this session; it is not one of Xcode's actual
  configured teams and the entitlements/`DEVELOPMENT_TEAM` changes were reverted. Xcode's real
  accounts include several paid company teams (e.g. "Aksis Bil. Hiz. ve Dan. A.S" / `3SFM6JC478`)
  and one free Personal Team (`Y592TH6PR3`, cannot provision CloudKit).
- Spike R-1 on real hardware (watchOS 26 — Apple Watch Series 6).
- Schema promotion from development to production.
- `cursor-agent`'s headless mode (`-p`/`--print`) is not authenticated even though interactive
  `cursor-agent whoami`/`login` succeed — its browser-session token isn't visible to headless
  invocations in this environment. Run `cursor-agent login` interactively (`!cursor-agent login`)
  if headless delegation to it is needed again; Claude did AppData's CloudKit-plumbing work directly
  this session instead.

# Completed Work

- **Milestone 0 — Foundation, complete.** Five packages, dependency-rule probe, `project.yml` +
  three app targets (macOS builds; iOS/watchOS blocked on watchOS SDK/runtime mismatch, see
  Outstanding above), all `docs/` written, `AppDataModelActor` wrapper removed in favor of
  repositories owning their `ModelContext` directly.
- **Milestone 1 — TimerDomain implemented and verified** (`xcrun swift test --package-path Packages/TimerDomain`).
- **Milestone 2 — TaskDomain implemented and verified** (`xcrun swift test --package-path Packages/TaskDomain`).
- **Milestone 3 — AppData (local) implemented and verified** (`xcrun swift test --package-path Packages/AppData`).

# Active Work

Milestone 4 construction half done. Waiting on a real Apple Developer Team ID to proceed to the
hardware/CloudKit half (entitlements, spike R-1, schema promotion).

# Architecture Decisions Made

All 14 ADRs are specified in `plans/plan01.md` §30 and written up in `docs/DECISIONS.md`.
The two that explain most of the codebase:

- **Task and Timer are independent domain packages**; a timer references a task only as `UUID?`.
- **Timer state is an append-only event log**, because SwiftData+CloudKit has no custom merge hook
  and property-level merging can produce timer states that never existed. Immutable events never
  merge. This drives the projection/evaluation split, arbitration, and the absence of stored
  derived state.

# Important Constraints

- Deployment floor **macOS 14 Sonoma · iOS 17 · watchOS 10** (ADR 014, Revision 2, 2026-08-09 — kept
  low deliberately to keep the real iPhone 11, capped at iOS 18.6.2, usable for testing); SDKs are
  26.x, so every Liquid Glass API needs an availability gate and **every platform ships two
  appearances**.
- Synced schema is frozen at **two entities**: `TaskRecord`, `TimerEventRecord`. No relationships,
  no unique attributes, all properties optional or defaulted. A separate non-mirrored container
  holds the WatchConnectivity staging store.
- Never synchronise a per-second value.
- `project()` is timeless; `evaluate(at:)` is time-dependent and persists nothing.
- Bundle prefix `com.diwan.TaskTracker`; container `iCloud.com.diwan.TaskTracker`.

# Known Issues

- **A stale Swift 5.0.3 toolchain shadows Xcode's.** A bare `swift build` fails with duplicate
  Foundation classes. Always use `xcrun`. Toolchain in use: Swift 6.3.3 / Xcode 26.6.
- **No real Apple Developer Team ID confirmed yet** — see Current Milestone. CloudKit entitlements
  are not configured in `project.yml`; do not re-add them without a verified Team ID (a cached
  codesign identity is not sufficient evidence — verify against
  `defaults read com.apple.dt.Xcode.plist IDEProvisioningTeamByIdentifier` or Xcode ▸ Settings ▸
  Accounts).

# Open Questions

None blocking Milestone 4 construction. CloudKit Team ID (see Current Milestone) blocks the
verification half only.

# Resolved

- **Deployment floor** (was: conflicted with available hardware). Went through two revisions on
  2026-08-09, both in `docs/DECISIONS.md` ADR 014:
  - **Revision 1**: raised to macOS 26 / iOS 26 / watchOS 26 everywhere, seam deleted. Reasoning at
    the time: the only paired Watch is a Series 6 on watchOS 26.0, so a watchOS 11 floor could never
    be verified on real hardware. This checked the Watch but never checked the paired iPhones.
  - **Revision 2 (final)**: reverted back down to macOS 14 / iOS 17 / watchOS 10, dual-appearance
    seam restored. The full device check that should have happened before Revision 1 found the real
    roster: Mac macOS 26.5.2, iPhone 13 mini iOS 26.6, Watch watchOS 26.0, but **iPhone 11 iOS
    18.6.2 — hardware-capped, cannot reach 26**. A 26-everywhere floor would have silently retired
    the iPhone 11 as a test device; the user wants broad real-device reach instead.
  - `AppDesign` had no compatibility-seam code at any point, so both revisions were documentation +
    `project.yml` + package-manifest changes only, never a code rollback.
  - **Lesson**: check the full real-device roster (`xcrun devicectl list devices`, then
    `devicectl device info details --device <id>` for `osVersionNumber`) before setting or revising
    a deployment floor — not just the one device that happens to be top of mind.
- **macOS app scope** (was: menu-bar-only vs. also needing a manage/edit surface). Resolved
  2026-08-09: `MenuBarExtra(.window)` stays the primary, `LSUIElement` surface; it opens a singleton
  auxiliary `Window` for the full task hub (manage/edit tasks) on demand. See `docs/ARCHITECTURE.md`
  and `docs/ROADMAP.md` M5.
- **Cursor CLI authentication** (was: not authenticated). Now authenticated (`cursor-agent whoami`
  succeeds) — available for delegation again.
- **watchOS platform installed?** Yes, watchOS 11.5 and 26.0 simulator runtimes are present. The
  remaining build failure is a 26.5-specific runtime gap (see Known Issues), not a missing platform.

# Next Recommended Steps

1. Get a real Apple Developer Team ID from the user; wire up entitlements
   (`com.apple.developer.icloud-container-identifiers`, `com.apple.developer.icloud-services`) and
   `DEVELOPMENT_TEAM` in `project.yml` for all three app targets.
2. Point the three app targets at `AppDataModelContainer.makeSynced()` instead of
   `makeLocalInMemory()`.
3. Run spike R-1 on real hardware (Mac, iPhone, and the watchOS 26 Apple Watch Series 6); record
   results in `docs/ICLOUD_SYNC.md`.
4. Prove F8 (two-offline-starts, supersession permanence, duplicate delivery) on the actual
   two/three-device system, cross-checked against `ConvergenceProofTests.swift`'s in-memory oracle.
5. Promote schema from development to production.
6. Milestone 4 verification; begin Milestone 5 (macOS app: MenuBarExtra primary + auxiliary
   task-hub window).

# Recent Changes

2026-08-09 — Milestone 4 construction half complete: `AppDataModelContainer.makeSynced()`,
convergence-proof tests, `ActiveTimerController`, throwaway Mac/iPhone shells. All five package
manifests bumped to swift-tools-version 6.2 / platforms 26 to match the ADR 014 revision. watchOS
26.5 simulator runtime installed; all three app schemes build zero-warning. `cursor-agent`'s headless
mode turned out not to be authenticated despite interactive login succeeding — its assigned task
(AppData CloudKit plumbing + tests) was done directly instead; opencode completed its half
(controller + shells) successfully and was verified independently.
2026-08-09 — Milestone 0 completed and committed (`6956a1d`): removed `AppDataModelActor` wrapper,
added `TIMER_ARCHITECTURE.md`/`DECISIONS.md`, fixed XcodeGen local-package folder refs. Deployment
floor raised to 26 everywhere (ADR 014 revision); macOS scope clarified (menu-bar primary + auxiliary
task-hub window). Milestone 4 started.
2026-08-09 — Fixed Xcode Issue Navigator spam about *Tests source paths: XcodeGen's local-package
folder refs were confusing SourceKit. `postGenCommand` now strips them
(`scripts/strip-local-package-folder-refs.py`). Layout was already correct; CLI tests were fine.
2026-08-09 — Plan approved. Milestone 0 started: packages, boundary probe, root docs.
