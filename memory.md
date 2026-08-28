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
  (`ModelConfiguration(cloudKitDatabase: .private(cloudKitContainerIdentifier))`). At the time this
  was written, "verified TaskRecord/TimerEventRecord satisfy the CloudKit contract" meant code
  inspection only — `.makeSynced()` was never actually launched until 2026-08-14, when it crashed
  immediately (see Active Work / Known Issues: non-optional stored properties are not actually
  CloudKit-safe even with a Swift init default). **Lesson: "verified" for a CloudKit contract claim
  must mean an actual `ModelContainer` construction against the real configuration, not code
  review** — the two are not equivalent and the gap went undetected for two milestones.
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

**Signing is now unblocked (2026-08-14).** The user's Apple Developer account (`MUHAMMED ELSAEED`,
team `925WW662VY`) was approved for the paid Individual Program — Xcode's cached
`IDEProvisioningTeamByIdentifier` confirms `isFreeProvisioningTeam = 0`, `teamType = Individual`
(was previously a free Personal Team, which cannot provision CloudKit). Steps taken:
- Added `DEVELOPMENT_TEAM: 925WW662VY` to `project.yml`'s base settings (applies to all three
  targets alongside the CloudKit entitlements already wired in — see git log for the earlier
  `T96KAT2Q28` false start, a cached codesign identity that wasn't a real signed-in account).
- `xcodebuild -allowProvisioningUpdates` initially failed with "device isn't registered" for this
  Mac; one interactive Xcode build (⌘B) registered the Mac's UDID with the account. After that, CLI
  builds with `-allowProvisioningUpdates` succeed unattended.
- All three schemes (`TaskTracker-macOS`, `TaskTracker-iOS`, `TaskTracker-watchOS`) now build and
  codesign clean from the CLI, signed "Apple Development: mohamed.elsaeed276@icloud.com
  (5MU3H3K8KR)", CloudKit entitlements included.
- Switched `Apps/macOS/TaskTrackerApp.swift` and `Apps/iOS/TaskTrackerApp.swift` from
  `AppDataModelContainer.makeLocalInMemory()` to `.makeSynced()` — both rebuilt clean afterward.
- All 25 package tests still pass (`xcrun swift test` in TimerDomain, TaskDomain, AppData).

Still outstanding:
- Spike R-1 on real hardware (watchOS 26 — Apple Watch Series 6; also verify against the floor —
  iPhone 11, iOS 18.6.2). Not yet run — requires installing the synced build on real devices and
  observing actual CloudKit propagation, which hasn't happened yet.
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

**2026-08-24 — Today row custom swipe actions + configurable row inputs (iOS).** `TodayTaskRow`
is now fully configurable through its initializer: `onTap`, `onLongTap`, `onComplete`,
`ltrSwipe`/`rtlSwipe` (`TodayRowSwipeAction`: symbol + label + tint + async handler),
and an optional inline trailing `inlineAction`. Every parameter defaults — omitting one yields
the standard behavior (tap = open editor, leading swipe = context-aware Done/Not-done full-swipe,
trailing = Remove-from-Today full-swipe). Swipe actions are plain-value structs, deliberately NOT
stored `Button` views or `UIImage` (owner's draft direction kept: tap/RTL/LTR/long-press/
complete/inline-action slots; storage form corrected to closures + values per the "components
take plain values" rule; a stored `Button` can't carry tint/accessibility wiring). Long press and
tap share one `.gesture(LongPress…exclusively(before: Tap))` so holding suppresses the tap.
Leading-edge Edit button replaced by tap-to-edit. Both new SF Symbols (`edit`, `removeFromToday`)
added to `AppSymbols.Tasks`; the `"calendar.badge.minus"` literal is gone. Liquid Glass on rows
was requested but rejected — `docs/DESIGN_SYSTEM.md` bans glass on list content; user confirmed
respecting the doc. Six `TodayTaskRow` previews added via a `TodayRowPreviewScaffold` (rows in a
real List — swipeActions need one — with a monospaced footer echoing which callback fired):
defaults incomplete+completed, custom LTR/RTL swipes, inline trailing action, tap-vs-long-press,
long-content clamp, fully customized, and very-large-title (default + `.accessibility1` Dynamic
Type). The inline trailing action gained `AppSpacing.s` trailing padding so it no longer touches
the row's end. Verified: all three schemes build zero-warning,
AppFeature 53 tests pass.

**2026-08-24 — TaskRow extracted to AppDesign (plan taskrow-extraction Tasks 1 + 3 done).**
The row moved out of `Apps/iOS/TodayTabView.swift` into
`Packages/AppDesign/Sources/AppDesign/TaskRow.swift` as a public plain-values component:
`TaskRow(title:notes:priorityLabel:isCompleted:leading:trailing:onPress:)` with nested
`LeadingAction(isOn:tint:action:)` / `TrailingAction(icon:tint:accessibilityLabel:action:)`
structs; callers attach `.swipeActions` externally. The private `TodayTaskRow`,
`TodayRowInlineAction`, and all row previews were deleted from TodayTabView; the app-side glue
(`TodayRowSwipeAction` with `standardCompletion(task:today:onFinish:)` — `onFinish` restores the
post-completion `pool.reload()` — and `standardRemoveFromToday`) plus a private `swipeButton`
helper stay in the iOS file. Priority capsule badge support added. Preview scaffold ported as
DEBUG-only `TaskRowPreviewScaffold`; two cross-platform fixes were needed because AppDesign
builds for every target: `.listStyle(.insetGrouped)` is unavailable on macOS (dropped) and
`.background(.bar)` on watchOS (now `.quaternary`). Plan acceptance boxes ticked for Tasks 1
and 3; Tasks 2 (PoolPreferences), 4 (PoolTabView), and 5 (SettingsTabView) remain open.
Verified: AppDesign package builds clean and its 10 tests pass, iOS/macOS/watchOS schemes build
zero-warning (only pre-existing LanguageBundle Sendable warning + toolchain noise),
AppFeature 53 tests pass. Not verified in this session: visual canvas inspection of previews.

Completion animation added to `TaskCompletionMark` (TimerControls.swift) so every row inherits
it. First attempt used conditional insertion plus a `@State pulse`, but the pulse often started in
its final state and appeared static. Corrected implementation keeps the fill and checkmark in the
view tree and animates `opacity` + `scaleEffect` directly from `isCompleted` with a spring
(`response 0.28 / damping 0.52`), so completion and un-completion both interpolate reliably. Title
strikethrough/fade in `TaskRow` animates over 0.2 s. All three schemes rebuilt zero-warning;
AppDesign 10 tests pass.

Temporary DEBUG-only `TaskRow` animation logs added for diagnosis: tapping the leading completion
button prints `[TaskRow animation] completion button pressed; currentVisualState=...`, and any
`completionVisualState` change prints `completion visual state changed old -> new`. Logs avoid task
titles/content to prevent accidental PII in console output. AppDesign 10 tests and all three app
scheme builds pass after adding the logs.

Runtime log showed only `completion button pressed` and no state-change log, proving the row tap
arrived but the stateless row was waiting on the async controller/model update; inside `List`, that
can redraw straight to the completed value with no visible interpolation. `TaskRow` now owns a local
`@State displayedCompletionState`: on leading-button press it optimistically toggles the visual state
inside `withAnimation`, logs the local visual set, then runs the caller action; `onChange` of the
external completion value syncs swipes/controller updates back into the local state with the same
spring. This should make both tap-to-complete and LTR swipe completion visibly animate when the row
remains on screen.

Follow-up logs showed `TaskRow` did set local state, but Today completion removes the row from the
filtered list before the animation can be seen. `TodayTabView` now owns `completingTaskIDs`, passes
`task.isCompleted || completingTaskIDs.contains(task.id)` into `TaskRow`, and delays `today.complete`
until after the row animation window. Swipe completion uses the same path via
`completionSwipeAction(for:isShowingCompleted:)`. `TaskCompletionMark` now has an `animationToken`
that drives a visible expanding burst ring; `TaskRow` exposes its animation phase through the
completion button accessibility value (`incomplete`, `animating-to-completed`, etc.) for tests.
Added iOS UI test `testTodayCompletionButtonStartsCompletionAnimation`, which creates a Today task,
taps `taskRow.completionButton`, asserts `animating-to-completed`, then waits for the row to leave
Today. Xcode project regenerated from `project.yml` so UI tests are in the scheme. Verified targeted
iOS UI test passes, AppDesign 10 tests pass, AppFeature 53 tests pass, and iOS/macOS/watchOS builds
are warning-free after fixing the `withAnimation`/`Set.insert` warning.

Console-log follow-up: the CloudKit `CKAccountStatusNoAccount` lines are documented expected
behaviour for a simulator not signed into iCloud (`docs/ICLOUD_SYNC.md` §Simulator / no iCloud
account), so no sync-architecture change was made. The `Invalid frame dimension (negative or
non-finite)` source was `Apps/iOS/PoolTabView.swift`, where `PoolControlPanel` computed
`.frame(height: (1 - progress) * .infinity)`. Fixed by measuring the expanded header's finite
intrinsic height with `PoolControlPanelExpandedHeightKey` and animating `measuredHeight *
(1 - progress)` instead. Latest targeted animation UI test output contained no `Invalid frame`
lines; AppDesign 10 tests, AppFeature 53 tests, and iOS/macOS/watchOS builds pass.

**2026-08-18 — Pool improvements branch.** Branch `feature/pool-improvements` redesigns the iOS Pool
screen around Reminders-style category cards: Today, All Tasks, Scheduled, Archived, and Completed. The
controller now loads one all-task snapshot and filters `visibleTasks` by selected card, with counts per
category and existing sort orders preserved. Scheduled includes active tasks with any scheduled day. The
row-level Today add action appears for unscheduled tasks and tasks scheduled for a non-today day, then
reschedules them to today. Archived currently maps to completed tasks because the domain model still has
no separate archived field.

**2026-08-17 — iOS native tab-bar Add/search branch.** Branch `feature/ios-tabbar-add-task` keeps
the tab bar navigational by using SwiftUI's native `Tab(role: .search)` Add item on iOS 18+ with the
outline `plus.rectangle` SF Symbol; on iOS 26+ the tab-bar item activates the system search-field morph via
`.tabViewSearchActivation(.searchTabSelection)`, and the Add page repeats the symbol with Draw On motion
when it opens. iOS 17 keeps the separated circular Add-button fallback using the same static symbol. The
shared add/search flow replaced the pinned Today/Pool fields: From Today, submit/suggestion schedules for
Today; from Pool or other tabs, submit adds to Pool and suggestions open the Pool task detail. Verified on
iOS 26.5 simulator with focused UI tests for Today quick-add and Pool multiple quick-add.
Follow-up in the same branch removed task-detail auto-focus so opening details does not raise the
keyboard, and removed the app-wide per-second active timer strip from non-Timer tabs.

**2026-08-17 — iOS Spotlight-style quick entry branch.** Branch
`feature/ios-spotlight-quick-entry` moves the shared Today/Pool add/search field out of the list and
into a bottom safe-area control. It rises above the keyboard via SwiftUI keyboard avoidance and shows
matching existing-task suggestions above the field. Verified with `TaskTracker-iOS` Debug build.

**2026-08-16 — Timer dual display modes + cross-platform UI tests.** Timer tab now has two swipeable
pages (page dots, like Apple Clock) over the same `ActiveTimerController`: a list-row countdown
(`TimerCountdownRow`, large thin remaining + preset label + inline circular Pause/Resume) and an
analog stopwatch face (`StopwatchAnalogFace`, elapsed dial + `MM:SS.cs` digital + red `Ends` finish
time). Formatting-only APIs added to `ActiveTimerController` (`remainingListLabel`,
`sessionDurationLabel`, `elapsedStopwatchDigital`, `endTimeLabel`, `stopwatchHandAngles`, shared
`fireDate(at:)`); domain/timer engine unchanged. Pager is `TimerDisplayModePager` (`.page` TabView on
iOS/watchOS; dot buttons on macOS). Menu-bar panel shows list-row only (`showsStopwatch: false`);
Task Hub pane dial is 280 pt, watch 140 pt at 1 Hz. Also moved **Delete Task** into the form body
(its own destructive section in the iOS `TaskEditSheet` and macOS menu-bar edit cover), out from
under the Save button. UI tests: iOS 6/6 and watchOS 1/1 pass on simulator; added a watchOS UI-test
target (`TaskTracker-watchOS-UITests`) and an in-memory `--ui-testing` switch to the watch app (it
previously always used `.makeSynced()`). macOS UI tests remain **blocked**: added an
`NSApplicationDelegateAdaptor` that calls `setActivationPolicy(.regular)` under `--ui-testing`
(fixes the earlier "Running Background"/activation error), but XCUITest then fails with
`Application '…' has not loaded accessibility` — a known limitation of driving a `LSUIElement`
menu-bar app from CLI `xcodebuild` (the accessibility tree never loads headlessly). Run macOS UI
tests from Xcode instead. Key lesson: a `.accessibilityIdentifier`/`.accessibilityLabel` on a
non-element container in SwiftUI propagates to every descendant and overrides their own
identifiers — keep container identifiers off pager pages/rows.

**2026-08-16 — F9 slice + Pool/Today UX.** Per-task Time Spent on iOS edit sheet: project sessions by
`relatedTaskID`, total with supersession cutoffs; add/edit/delete via synced `TaskTimeAdjustment`;
hide sessions via `TaskSessionExclusion` (events stay append-only). Today hides completed tasks;
Pool Active/Completed + sort; Delete Task on edit sheet. AppFeature 42 tests + AppData 9 pass;
`TaskTracker-iOS` builds.

**2026-08-16 — Timer↔task navigation + timer action bar (iOS).** App-wide `TaskTimerActionBar` above
the tab bar while a session is active (not on Timer tab). Linked task sheet hosts the strip without
Open Task. Bar can jump to Timer and to the linked task.

**2026-08-16 — iOS Timer tab deep link from Live Activity + start-from-task.** Live Activity taps
only cold-opened the app (no `widgetURL`). Task “Start Timer” dismissed the sheet but left the
user on Today/Pool. Added `tasktracker://timer` (`TaskTrackerDeepLink`), `widgetURL`/`Link` on the
Live Activity, selectable `AppTabView` + `AppRootTab`, `.onOpenURL` → Timer tab, and
`onStartedTimer` from edit sheet / Pool context menu.

**2026-08-16 — CloudKit remote-notification background mode + aps-environment.** iPhone logs showed
`BUG IN CLIENT OF CLOUDKIT: … require the 'remote-notification' background mode` and
`CKAccountStatusNoAccount` on the simulator. Fixed the former in `project.yml` for macOS/iOS/watchOS
(`UIBackgroundModes: [remote-notification]`, `aps-environment: development`) and made the iOS source
`Info.plist` explicit so the built app carries the array after regeneration. The latter is
environment: sign the simulator/device into iCloud — not an app bug. Documented in
`docs/ICLOUD_SYNC.md`.

**2026-08-16 — menu-bar edit form scrolls; Cancel/Save stay pinned.** Owner: Edit Task clipped
with no scroll when the timer hint made the form taller than the panel. Fields live in a
`ScrollView`; Cancel/Save stay outside it at the bottom.

**2026-08-16 — macOS “Live Activity” = menu-bar countdown (not ActivityKit).** Owner expected a
Live Activity on Mac; ActivityKit cannot author Live Activities on macOS (iPhone/iPad only;
Continuity may mirror from phone). Restored `MenuBarStatusLabel`: idle shows the app icon template,
active shows `compactLabel` via `TimelineView` (plan §21). Expiry still handled by
`ActiveTimerExpiryRefreshLoop` — no per-tick `.task` on the label (avoids the earlier MenuBarExtra
re-render loop).

**2026-08-16 — Pause no longer blocks starting another task timer; Stop ≠ continue.** Owner:
after Pause, Start Timer / Run were disabled (`!timer.isActive`), forcing Stop — which ends the
session permanently so it cannot be resumed. Domain already allows start-while-active (supersession).
UI now keeps task Start/Run enabled (label becomes Replace when active) and explains Pause/Resume
vs Stop. Live Activities remain **iOS-only** (ActivityKit); macOS menu-bar Edit Task cannot show
them. Hardened iOS adapter (log auth failures; stop swallowing `Activity.request` errors); widget
Info.plist sets `NSSupportsLiveActivities`. CloudKit spike logs in the report look healthy —
`BGSystemTaskSchedulerErrorDomain Code=3` / remote-notification waits are expected Mac noise.

**2026-08-15 — Task Hub checkbox completes tasks.** Owner: checkbox in the macOS Tasks window did
not mark done. Root causes: hollow `TaskCompletionMark` missed hit-testing (fixed in AppDesign with
`.contentShape`), and `.plain` buttons inside a selectable `List` lose clicks to row selection
(TodayRow now `.borderless`). UI test: `testTaskHubCheckboxCompletesTask`.

**2026-08-15 — menu-bar Today row: title opens details; trailing Run is primary.** Owner feedback:
tapping the task name marked it done (the whole leading block was one complete button), and the
trailing pencil should become a **Run** action. Split the row: circle-only complete/uncomplete;
title/notes open the existing inline details cover; trailing control is `.borderedProminent` play
(`AppSymbols.Timer.resume`), disabled while a timer is active, starts `timer.start(relatedTaskID:)`
and switches to the Timer tab. UI tests updated (`testMenuBarTitleTapOpensInlineDetailsAndSaves`,
`testMenuBarRunButtonStartsTimer`).

**2026-08-15 — Edit sheet + Live Activities ship.** Date (`scheduledDay`), priority
(`TaskPriority`), and start-timer-for-task (`relatedTaskID`) are on the iOS edit sheet and macOS
Tasks hub editor. Live Activities: `TaskTracker-iOS-Widget` + ActivityKit adapter wired through
`TimerLiveActivityControlling` (fire dates only — never remaining seconds). Package tests: 70
passing. All three app schemes build. Follow-up Liquid Glass pass: shaped
`.navigationSurface()` / new `.panelChromeSurface()`, removed nested glass on menu-bar edit,
floating Save/Open Tasks controls — flat opaque menu-bar look was a seam bug, not missing call sites.

**2026-08-15 — menu-bar panel Today/Timer switched to segmented tabs.** Owner feedback: stacking
Today + Timer in one popover felt cramped. `MenuBarPanel` now uses a segmented `Picker`
(`menubar.panel.tabPicker`) so only one surface shows at a time; Open Tasks / Preferences stay
pinned below. Defaults to Today; one-shot prefers Timer when `timer.isActive` on appear (resets on
disappear so reopen re-evaluates without fighting in-session switches). New UI tests cover tab
switch and active-timer default. `MenuBarTodaySection` / `TimerSectionView` / Task hub untouched.
**Independently verified by me**: full macOS UI suite run three times, 7/7 pass every time
(`** TEST SUCCEEDED **`), all 67 package tests pass, all three schemes build clean. One transient
environment hiccup along the way — a UI-test authorization failure ("Not authorized for performing
UI testing actions") that resolved itself on retry with no permission/code change, unrelated to the
one-time Accessibility gate documented elsewhere in this file.

**2026-08-15 — two more real menu-bar bugs found and fixed, confirmed via new automated tests
(twice, not flaky).** User report: tapping a Today task's title marked it complete, but tapping the
circle checkbox next to it did not; and there was no way to edit a task from the menu bar at all.
- **Circle tap not completing the task.** `TaskCompletionMark` is a hollow, stroked (unfilled)
  `Circle` — its empty interior isn't actually drawn, so macOS's default hit-testing didn't count
  clicks landing there as hits on the row's `Button`, only clicks on the title text (real drawn
  content) registered. Fixed with `.contentShape(Rectangle())` on the button's label, forcing the
  whole row's bounding box to be tappable uniformly. New test `testMenuBarCircleTapCompletesTask`
  specifically clicks the leading 6% of the row (where the circle sits, not the text) and asserts
  completion — passed twice.
- **No edit affordance in the menu bar.** First attempt (superseded same day): a pencil-icon Edit
  button that opened the Tasks window via a shared `TaskEditRequest` coordinator and auto-selected
  the task there. User reported "when I press on edit it is not opening" and asked for a design
  change instead: **edit inline in the bar** (a small form right in the popover), leaving the app's
  own Tasks-window edit page completely separate and unchanged. Implemented that: `MenuBarTodaySection`
  now has local `editingTaskID`/`editTitle`/`editNotes` state; clicking Edit shows a
  `MenuBarTaskEditForm` (title/notes fields + Save/Cancel) inline, calling
  `TodayController.edit(...)` directly — no window, no `NSApp.activate`, no cross-scene
  coordination at all. **`TaskEditRequest` was removed entirely** (dead code once the window-based
  approach was dropped) along with all its wiring in `TaskTrackerApp.swift`/`TaskHubView.swift`.
  This also sidesteps the whole class of menu-bar-to-window focus/activation flakiness that had
  already caused problems once (Open Tasks/Settings, see below) — a quick edit no longer depends on
  it at all. New test `testMenuBarEditButtonShowsInlineFormAndSaves`: clicks Edit, asserts **no**
  "Tasks" window exists, finds the inline title field pre-filled with the task's title, retypes it,
  saves, and confirms the row updates with the new title — passed twice.

macOS UI suite: **5/5 pass**, run twice to rule out flakiness, both `** TEST SUCCEEDED **`. All 67
package tests still pass. All three schemes still build clean.

**2026-08-15 — comprehensive test-layer expansion complete; macOS "Open Tasks"/Settings/quick-add
fix CONFIRMED via real automated UI tests (twice, not flaky).** Added broad new coverage across
unit/integration/UI layers: TimerDomain 15 tests, TaskDomain 4, AppData 9, AppFeature 33, AppDesign
6 (**67 package tests total, all passing**); XCUITest targets for iOS and macOS added through
`project.yml`. iOS UI suite: 3/3 pass (Today quick-add, Pool multi-add visibility, Timer
start/pause-stop). macOS UI suite initially blocked by a one-time Accessibility/Automation
permission gate ("Timed out while enabling automation mode") — that gate cleared partway through
this session (environment-side, not something either Cursor or I did), and running the real macOS
UI tests surfaced and resolved three genuine issues:
- **The actual bug the user reported — Today tasks added via the menu-bar panel never appeared.**
  Confirmed via the XCUITest's captured accessibility snapshot: the `ScrollView` wrapping the task
  list rendered at literally zero height (`{298.0, 0.0}}`) because `.frame(maxHeight: 220)` alone
  gives no floor — inside a `MenuBarExtra` popover's auto-sizing `VStack`, the ScrollView's ideal
  height is ambiguous and it collapses. The task was being added correctly the entire time; it had
  nowhere visible to render. Fixed with `.frame(minHeight: 44, maxHeight: 220)` in
  `Apps/macOS/TaskTrackerApp.swift`'s `MenuBarTodaySection`.
- **A real accessibility bug found along the way**: the task row's `.accessibilityLabel` was
  overridden to just "Mark complete"/"Mark incomplete" with no task title — a VoiceOver user
  couldn't tell which task. Fixed to include the title.
- **The earlier `NSApp.activate(ignoringOtherApps: true)` fix for "Open Tasks"/Settings was
  confirmed genuinely correct** — accessibility snapshots showed the Settings window as
  `Keyboard Focused` (truly active) with real content, and the Tasks window opening with its full
  `NavigationSplitView` sidebar and content. The two test *failures* for these were bugs in the
  tests themselves: `app.otherElements["taskHub.root"]`/`["preferences.form"]` queried the wrong
  XCUIElement type — `NavigationSplitView`/`Form` don't bridge to `.other`, and a custom
  `.accessibilityIdentifier` on a `NavigationSplitView` specifically gets absorbed into SwiftUI's
  own internal identifier on macOS rather than exposed as given (confirmed via the captured tree:
  it reported as `"task-hub, SidebarNavigationSplitView"`, never `"taskHub.root"`) — a SwiftUI
  limitation for that container, not an app bug. Fixed the tests to check real, reliably-present
  content instead, and removed the non-functional identifier from `TaskHubView.swift`.

**Final state, verified by me directly, twice for the macOS suite to rule out flakiness:** all 67
package tests pass, iOS UI suite 3/3, macOS UI suite 3/3 (both runs `** TEST SUCCEEDED **`), all
three app schemes build clean. Everything the user reported this session — Mac app appearing frozen
(CPU spin), Pool not showing all tasks, rough task editing, cramped mobile timer, Open Tasks/Settings
inert, Today tasks not appearing in the bar — is now fixed and covered by a real, repeatable
automated regression test, not just a one-time manual check.

**Critical bug fixed + full redesign, 2026-08-15, independently verified.** The user reported real
problems from testing on actual hardware (not simulators): "Mac app is not showing," Pool tab
missing tasks, a rough task-edit experience, and a cramped mobile timer UI. Investigation (my own,
via `sample`/CPU profiling — not guessed) found the real cause of "Mac app not showing": the macOS
app was pegged at ~99% CPU, sustained, confirmed via `sample <pid> 3` showing 887/1613 samples stuck
in `MenuBarExtraController.updateButton` → `NSStatusBarButton setImage:` — a runaway re-render loop.
Root cause: `TimelineView(.periodic(from: .now, by: 1)) { ... .task(id: context.date) { ... } }`
(a pattern I'd added for M6's expiry-reload fix) loses its schedule identity inside `MenuBarExtra`'s
`label:` closure specifically and restarts near-instantly, spinning. Delegated the fix plus a
requested visual redesign ("Stopwatch app" for timer, "Reminders app" for task lists, all platforms)
to Cursor CLI in one large briefed task, since the file scope overlapped too much to parallelize.
**Fix verified independently by me, not trusted from Cursor's report:** relaunched the macOS binary
myself, confirmed CPU stayed at 0.0% over 20s of idle observation (was 99%+ sustained before) —
`ActiveTimerExpiryRefreshLoop` (new `AppFeature` type) now drives expiry checks via one app-lifetime
`Task { while true { ...; try? await Task.sleep(...) } }` loop, completely decoupled from SwiftUI's
render cycle; `TimerUI.timelineAnchor` (a fixed `Date`, not `.now`) is a second layer of defense on
any remaining `TimelineView` schedules. The Pool bug got a real fix too — a new AppData integration
test (`onDiskPoolQueryReturnsAllTasks`, using a genuine on-disk `ModelContainer`, not
`makeLocalInMemory()`) proved the repository layer was always correct; the actual bug was a missing
per-tab reload-on-reappear, fixed by adding `.task { await pool.reload() }` directly to
`PoolTabView`. Redesign verified via real simulator screenshots (Cursor's interactive testing,
cross-checked by me): iOS Today/Pool now read like Reminders (circular checkmarks, grouped rows,
"New task"/"New reminder" quick-add), Timer screens (macOS/iOS/watchOS) now read like Stopwatch
(large centered monospaced digits, green/red circular primary controls, Reset demoted to a small
destructive text link). 55 package tests pass (up from 48). All three schemes rebuild clean; macOS
and iOS both reinstalled/relaunched by me with no crash.

**Resolved 2026-08-15 — macOS surface split restructured, independently verified.** Menu-bar panel
now shows Today's tasks (compact, capped-height scroll list, quick-add, tap-to-complete) + Timer,
not Timer alone. The separate `Window` (`TaskHubView`) is now a `NavigationSplitView` with a
Today/Pool/Timer sidebar — the full app experience the user asked for ("app will be for all").
Timer UI is shared via a new `Apps/macOS/TimerSectionView.swift` (extracted from the panel) so the
menu-bar and window Timer sections can't visually/behaviorally drift apart — both use
`TimerUI.timelineAnchor` (fixed anchor) and the app-lifetime `ActiveTimerExpiryRefreshLoop`, not a
per-tick `.task(id:)`, so the earlier CPU-spin bug's exact trigger pattern was never reintroduced.
Verified myself: 52 package tests pass, macOS scheme builds clean, and — the load-bearing check —
CPU stayed at 0.0% across four 5-second samples with the app actually running, confirming the
restructuring didn't regress the CPU fix.

**App icon source created 2026-08-15** (found already in progress when this session picked up the
redesign task — not something I asked for, noting it exists rather than digging into provenance). `Design/AppIcon/AppIcon.icon` is an editable Apple Icon
Composer document, not a flattened image. It contains a native gradient background and one
`Timer System` group with separate ring, crown, four-marker, and checkmark layers; Liquid Glass is
deliberately restrained. Default, Dark, Mono, iOS/macOS, and circular watchOS
previews were inspected in Icon Composer. The document is deliberately not assigned to an Xcode
asset catalogue yet: the repository has three app targets and that target-level choice needs to be
made as a single explicit integration step. Supporting editable SVG construction layers live in
`Design/AppIcon/Source/`.

**Icon refinement 2026-08-15.** Removed the separate edge-highlight layer and disabled per-layer
glass effects for the ring, checkmark, and markers after Icon Composer generated intrusive
refraction lines. The native translucent group, soft shadow, and crown material remain; the
Default silhouette was rechecked in Icon Composer.

**Icon premium pass 2026-08-15.** Replaced the bright Azure foundation with a deep-sapphire native
gradient, increasing contrast and giving the cyan foreground a calmer, more first-party appearance
without reintroducing refraction effects.

**Crown refinement 2026-08-15.** Rebuilt the crown vector as a wider, low-profile button with an
simple geometry that rests directly on the ring; the collar and inner highlight were rejected as
too fussy. It remains the one foreground element using Icon Composer's per-layer Glass effect;
the Default preview was visually checked.

**Checkmark refinement 2026-08-15.** Reduced only the checkmark's vector scale and raised it
slightly for optical centering. The timer ring, crown, cardinal markers, background, and material
settings are unchanged. The editable SVG and the Icon Composer-imported copy were updated; a
post-save Composer visual inspection could not be completed because the open app stopped responding.

**Timer-ring color refinement 2026-08-15.** Kept the timer ring's exact path, thickness, and
placement, updating only its gradient to run from deep sapphire at the lower-left through blue to
soft cyan at the upper-right. The crown, cardinal markers, checkmark, background, and material
settings are unchanged. Both editable and Icon Composer-imported SVG copies match.

**Menu-bar glyph draft 2026-08-15.** Added a separate monochrome template source at
`Design/MenuBarIcon/TaskTrackerMenuBarGlyph.svg` plus a dark menu-bar preview. It now uses the
exact crown, open stopwatch-ring, marker, and checkmark vector paths from the full app icon in a
single-color template rendering for automatic light/dark system tinting. The preview preceded the
integration recorded next.

**Menu-bar icon integration 2026-08-15.** Wired the approved template glyph into the idle macOS
`MenuBarExtra` label via `Apps/macOS/MenuBarStatusIcon.swift`. It renders the full app icon's exact
crown, ring, marker, and checkmark paths at 18 pt as a template image, preserving system tint and
the existing state-dependent accessibility label plus Quit context menu.

**Menu-bar rendering repair 2026-08-15.** `Canvas` can draw blank within a `MenuBarExtra` label,
so the status label now uses `MenuBarStatusIcon.templateImage`: a native 18 pt `NSImage` template
drawn from the exact same vector paths. This keeps automatic menu-bar tinting while using the
reliable status-item image path.

Milestone 7 (watchOS app) implemented and independently verified 2026-08-15, plus the two gaps
deferred from M6's Codex review (macOS expiry notification, reset action) closed in the same
session. All three were run as two genuinely parallel Cursor CLI agents on different models
(`gpt-5.3-codex-high` for watchOS, `claude-opus-5-thinking-high` for the gaps), scoped to disjoint
file sets to avoid any merge conflict — confirmed conflict-free via `git status` after both landed.
Verification went beyond `xcodebuild` for all three platforms this time: macOS binary launched
directly, iOS and watchOS installed and launched on a newly-paired iPhone 11 / Apple Watch Series 10
simulator pair, screenshots confirmed real rendering (watchOS: Idle state, two-page vertical
TabView; iOS: Timer tab with the new Reset button). No crashes, no new
`~/Library/Logs/DiagnosticReports/TaskTracker-*.ips`. 48 package tests pass (up from 44). Milestones
5/6 remain done. Milestone 4 construction half remains done; hardware/CloudKit half still blocked on
spike R-1. Next: install synced builds on real hardware and run spike R-1 — the last thing blocking
Milestone 4, and now the last thing blocking before Milestone 8 (Reliability) can meaningfully start,
since M8 needs the real convergence proof this unblocks.

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
  no unique attributes, **every stored property genuinely `Optional` (`?`)** — a Swift init default
  on a non-optional property does NOT satisfy SwiftData's CloudKit validation, see Known Issues. A
  separate non-mirrored container holds the WatchConnectivity staging store.
- Never synchronise a per-second value.
- `project()` is timeless; `evaluate(at:)` is time-dependent and persists nothing.
- Bundle IDs (macOS/iOS set 2026-08-14, watch corrected 2026-08-15, see Known Issues): macOS
  `com.diwan.TaskTracker-mac`, iOS `com.diwan.TaskTracker.app`, watchOS
  `com.diwan.TaskTracker.app.watch` (must be prefixed by the parent iOS app's bundle ID + `.` —
  Apple's WatchKit embedding rule, not optional). CloudKit container is unaffected:
  `iCloud.com.diwan.TaskTracker`.

# Known Issues

- **Resolved 2026-08-15 — timer never re-evaluated at expiry, staying stuck `.active` at `0:00`.**
  Codex review of the M6 diff caught this: `TimelineView(.periodic(from: .now, by: 1))` in both the
  iOS `TimerTabView` and macOS's `MenuBarStatusLabel`/`MenuBarPanel` reformats the countdown every
  second but never calls `reload()`, so `ActiveTimerController.state` only actually updates on an
  explicit action (start/pause/resume/stop) or initial `.task`. A timer reaching its fire date while
  the view stayed open would sit at `0:00` showing Pause/Stop forever instead of transitioning to
  `.completed(reason: .expired)`, contradicting `docs/TIMER_ARCHITECTURE.md`'s own rule that expiry
  is derived by evaluation. Fixed with `ActiveTimerController.reloadIfExpired(at:)` — a cheap
  in-memory check that only pays for a real `reload()` right at expiry — wired into all three
  `TimelineView` call sites via `.task(id: context.date)`. New regression test:
  `reloadIfExpiredTransitionsPastFireDate` in `AppFeatureTests.swift` (needed a new
  `MutableTimeSource` test double — `@unchecked Sendable` but confined to a single `@MainActor` test
  each use, which is the accepted exception, not a real-race workaround).
- **Resolved 2026-08-15 — watchOS bundle ID violated Apple's WatchKit embedding rule, blocking all
  real installation.** When the user set `com.diwan.TaskTracker.watch` directly in Xcode on
  2026-08-14 (fixing the App-ID-registration portal issue), it satisfied `xcodebuild` — the build
  succeeded — but `xcrun simctl install` (and, by the same rule, a real device install) failed
  outright: "WatchKit 2.0 app's bundle ID ... is not prefixed by the parent app's bundle ID followed
  by a '.'; expected prefix com.diwan.TaskTracker.app." **A clean `xcodebuild` does not prove an app
  is installable** — this is the second time actually running/installing the app (not just building
  it) caught something a build alone couldn't (see the CloudKit-contract entry below for the first).
  Fixed by renaming to `com.diwan.TaskTracker.app.watch` in `project.yml` (confirmed with the user
  first, since they'd asked not to have bundle IDs touched again without checking) — reinstalled and
  launched clean on the iPhone 11 simulator (`D763E055-1326-47A5-8068-6682ADC69ACC`), screenshot
  confirmed all four M6 tabs render.
- **Resolved 2026-08-14 — CloudKit contract violation that shipped since Milestone 3.**
  `TaskRecord`/`TimerEventRecord` declared several stored properties non-optional with only a Swift
  `init` default (e.g. `id: UUID = UUID()`). SwiftData's CloudKit mirroring validation checks true
  Optionality in the generated schema, not init defaults — this is invisible until a `ModelContainer`
  is actually constructed against a CloudKit-backed `ModelConfiguration`. Because the app was only
  ever run against `AppDataModelContainer.makeLocalInMemory()` until 2026-08-14 (when M5's macOS app
  was actually launched for the first time against `.makeSynced()`), this went undetected through
  two milestones despite a "verified the CloudKit contract" note in this file (see Current
  Milestone) — that verification was code inspection, not an actual container construction. Crashed
  with `Fatal error: 'try!' expression unexpectedly raised an error: SwiftDataError.loadIssueModelContainer`,
  diagnosed via the underlying CoreData error (run the binary directly, not via `open`, to see it:
  `.../TaskTracker.app/Contents/MacOS/TaskTracker`) — `NSLocalizedFailureReason` named every
  offending property. Fixed by making every flagged property genuinely `Optional` on the `@Model`
  and coalescing to the old defaults in `TaskMapping`/`TimerEventMapping.toDomain` — see
  `docs/DATA_MODEL.md`. One knock-on fix: `#Predicate { $0.id == task.id }` in
  `SwiftDataTaskRepository.upsert` failed to compile after `TaskRecord.id` became `UUID?` (a
  `#Predicate`-macro-specific type-checker quirk resolving `task.id` against the wrong `Identifiable`
  conformance) — fixed by lifting `task.id` to a local `let` before the predicate closure, same
  pattern already used elsewhere in that file.
  **Lesson: "verified" for a CloudKit-contract claim must mean actually constructing the
  `ModelContainer` against the CloudKit configuration, not code review — always run the app at least
  once against `.makeSynced()` (not just build it) after any `@Model` schema change, on every
  platform.**
- **A stale Swift 5.0.3 toolchain shadows Xcode's.** A bare `swift build` fails with duplicate
  Foundation classes. Always use `xcrun`. Toolchain in use: Swift 6.3.3 / Xcode 26.6.
- **Resolved 2026-08-14**: real, verified paid Apple Developer Team ID (`925WW662VY`,
  `MUHAMMED ELSAEED`, Individual) now wired into `project.yml` as `DEVELOPMENT_TEAM`. Verified via
  `defaults read com.apple.dt.Xcode.plist IDEProvisioningTeamByIdentifier` showing
  `isFreeProvisioningTeam = 0` before trusting it — do the same check before trusting any future
  team ID, since Xcode's cache can lag a fresh paid enrollment.

# Open Questions

None blocking Milestone 4 construction. CloudKit Team ID (see Current Milestone) blocks the
verification half only.

**Resolved 2026-08-15** (was the M6 open question above): `AppTabView { }` three-way seam added to
`AppDesign` — see Known Issues and `docs/DESIGN_SYSTEM.md`'s seam table.

**From M6's Codex review — three known gaps; two closed 2026-08-15, one still deferred:**
- **Resolved 2026-08-15 — macOS expiry notification.** `Apps/macOS/UserNotificationsTimerExpiryNotifier.swift`
  (new file, ported from the iOS one) now wires into `ActiveTimerController` construction in
  `Apps/macOS/TaskTrackerApp.swift`, same as iOS.
- **Resolved 2026-08-15 — reset action.** `ActiveTimerController.reset()` added, mirroring `stop()`'s
  shape exactly (reload, guard `.active`, tick clock, append a `.reset`-kind `TimerEvent`, reload —
  the trailing `reload()` is what cancels the pending expiry notification via
  `syncExpiryNotification()`, no special-casing needed). Reset buttons added to both macOS's
  `MenuBarPanel` and iOS's `TimerTabView`, `.disabled(!timer.isActive)`, behind a
  `confirmationDialog` pointing at Stop as the history-retaining alternative — Stop itself and its
  ⌘. shortcut are untouched, so "the user can always stop whatever timer is active" still holds.
  **Important catch, not something I asked for:** `reset()` also checks
  `TimerAuthoringPolicy.isAuthorable(.reset, quarantined:)` before authoring — `docs/TIMER_ARCHITECTURE.md`
  requires `.reset` be withheld from a quarantined session (a stale client must not erase history it
  can't interpret), and `TimerAuthoringPolicy` already existed in `TimerDomain` for exactly this with
  no caller until now. Emitting `.reset` unconditionally would have been the first violation of that
  rule in the codebase.
- **Resolved 2026-08-15 — the two follow-up gaps Track B surfaced, fixed directly (not delegated,
  small and well-understood):** `pause()` and `resume()` now consult `TimerAuthoringPolicy` the same
  way `reset()` does, withheld under quarantine per `docs/TIMER_ARCHITECTURE.md` — new tests
  `pauseWithheldWhileQuarantined` / `resumeWithheldWhileQuarantined` in `AppFeatureTests.swift`,
  mirroring `resetWithheldWhileQuarantined`'s shape. Also added the missing `TimerDomain`-level test
  (`resetDiscardsElapsedTime` in `TimerDomainTests.swift`) directly asserting `.reset` → `.idle` +
  zeroed `accumulatedActive` at the domain layer, not just the AppFeature integration layer. 51
  package tests now (was 48).
- **Still deferred — no task-linked timer starts.** `ActiveTimerController.start` always authors
  `relatedTaskID: nil`; no UI offers "start a timer for this task." Natural fit for **Milestone 8**
  (History and per-task totals, F9) since that milestone needs `relatedTaskID` wired up anyway to
  query timer events per task — don't build this piecemeal before then.

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

1. Run spike R-1 on real hardware (Mac, iPhone 11 @ iOS 18.6.2, and the watchOS 26 Apple Watch
   Series 6); record results in `docs/ICLOUD_SYNC.md`.
2. Prove F8 (two-offline-starts, supersession permanence, duplicate delivery) on the actual
   two/three-device system, cross-checked against `ConvergenceProofTests.swift`'s in-memory oracle.
3. Promote schema from development to production.
4. Milestone 4 verification; begin Milestone 5 (macOS app: MenuBarExtra primary + auxiliary
   task-hub window).

# Recent Changes

2026-08-15 — Reliability test expansion (unit + integration + UI): `TimerDomainTests` expanded to
15 tests with direct checks for projection timelessness, bounded/full-log evaluation equivalence,
device-ID tie arbitration, elapsed/remaining pause-resume math, and explicit transition-matrix
valid/invalid coverage. `TaskDomainTests` strengthened DayKey timezone/DST assertions. AppFeature
edge cases added (`TodayController.edit`/`PoolController.edit` empty-title rejection, Pool search
emoji/special-char filtering, rapid start→stop convergence). AppData integration added real on-disk
reopen tests for Today reload-composition and timer-event round trips + evaluation parity, and
extracted/tested `AppDataModelContainer.shouldPostRemoteChangeNotification(...)`. AppDesign tests
grew to 6 (tokens + tone-color mapping + fixed timeline anchor). Added XcodeGen UI-test targets
(`TaskTracker-iOS-UITests`, `TaskTracker-macOS-UITests`) + new XCUITests. Verification status:
all package suites green (67 tests total), iOS UI tests green (3/3), macOS UI runner blocked by
"Timed out while enabling automation mode" before test execution.

2026-08-15 — Milestone 7 (watchOS app) + two deferred M6 gaps closed, run as two parallel Cursor CLI
agents (different models, disjoint file scopes, no conflict): standalone watchOS app
(`WatchRootView`/`ActiveTimerScreen`/`TodayScreen`, `.tabViewStyle(.verticalPage)`, reused
`ActiveTimerController`/`TodayController` read-only); macOS expiry notification port; `reset()` on
`ActiveTimerController` with quarantine-authoring awareness neither task explicitly asked for but
both correctly found in `docs/TIMER_ARCHITECTURE.md`. Verified on real installs, not just builds, on
all three platforms — paired an iPhone 11 simulator with an Apple Watch Series 10 simulator
specifically to test the watch app, screenshots confirmed rendering. One small fix of my own: the
watchOS Start button used the wrong SF Symbol (`timer` instead of `play.fill`). 48 package tests
pass.
2026-08-15 — Milestone 6 (iOS app, MVP 1): `AppTabView` in AppDesign; `TimerExpiryNotifying` +
wiring in `ActiveTimerController` (spy-tested, no real `UNUserNotificationCenter` in package
tests); iOS tabs Today/Pool/Timer/Settings with presets 15/25/30/45/60, edit sheet, Pool swipe +
context menu; real notifier + permission request live only in `Apps/iOS`.
2026-08-14 — Codex review (`codex review --uncommitted`) of the M5 + CloudKit-fix diff found one
real [P1]: the CloudKit remote-import observer (added earlier today for spike R-1) only logged —
nothing told `ActiveTimerController`/`TodayController`/`PoolController` to reload when another
device's data mirrored in, so cross-device sync was invisible without a manual relaunch. Fixed:
`AppDataModelContainer.remoteChangeNotification` (a plain `Notification.Name`, posted only on a
succeeded `.import` event with a non-nil `endDate`) is now posted from `AppData`; a new
`RemoteChangeCoordinator` in `Apps/macOS/TaskTrackerApp.swift` observes it and reloads all three
controllers. Deliberately placed at the app layer, not in `AppFeature` or `AppData` — neither
package may know about the other's types (AGENTS.md), and the app layer already imports both. Hit
one Swift 6 strict-concurrency snag: a `deinit` touching the (non-`Sendable`) `NSObjectProtocol`
observer token from a nonisolated context didn't compile — resolved by dropping the `deinit`
entirely rather than reaching for `@unchecked Sendable`, since the coordinator is intentionally
app-lifetime (owned by `@main App`'s stored properties, never deallocated). Rebuilt all three
schemes, reran all 37 package tests, relaunched the binary directly again — clean.
2026-08-14 — Fixed a real crash-on-launch found by actually running the built macOS app (not just
building it): `TaskRecord`/`TimerEventRecord` had non-optional stored properties with only Swift
init defaults, which SwiftData's CloudKit validation rejects — `.makeSynced()` had never actually
been launched before M5's macOS app was run for the first time today. Made every flagged property
genuinely `Optional`, coalesced to the same defaults in the mapping layer, fixed one knock-on
`#Predicate` compile error in `SwiftDataTaskRepository.upsert`. All 37 package tests and all three
app schemes verified clean afterward; relaunched the macOS binary directly to confirm no crash and
no new `~/Library/Logs/DiagnosticReports/TaskTracker-*.ips`. `docs/DATA_MODEL.md` corrected to match
(was documenting non-optional types) — see Known Issues for the full story and lesson.
2026-08-14 — Milestone 5 (macOS app, MVP 1): TodayController and PoolController in AppFeature;
AppDesign v1 seams (`.navigationSurface()`, `.floatingControlSurface()`, `SurfaceGroup`); macOS
MenuBarExtra panel (SF Symbol idle / monospaced countdown when active) plus singleton `Window`
task hub (Today, Pool search, quick-add) and a minimal Settings scene. `compactLabel` formats
`TimerCalculator.remaining(_:at:)` — no timer arithmetic in views.
2026-08-14 — Bundle ID change: the original single shared bundle ID `com.diwan.TaskTracker` (used
identically by both macOS and iOS targets) started failing App ID registration on Apple's developer
portal ("cannot be registered... not available") for all three targets simultaneously — this
surfaced right after an unrelated entitlements fix (stripping a stray App Group Xcode had silently
added), but reproduced even for the watchOS target, which never had that entitlement, so it was a
portal-side state issue, not caused by the entitlements change. Resolved by the user setting new,
distinct bundle IDs directly in Xcode: macOS `com.diwan.TaskTracker-mac`, iOS
`com.diwan.TaskTracker.app`, watchOS `com.diwan.TaskTracker.watch` (companion ID updated to match).
`project.yml` updated to match so `xcodegen generate` doesn't revert it. All three schemes rebuilt
clean afterward; CloudKit container identifier (`iCloud.com.diwan.TaskTracker`) unaffected. **Do not
change these bundle IDs again without the user's say-so** — this was their fix.
2026-08-14 — Spike R-1 instrumentation in AppData: `os.Logger` (subsystem `com.diwan.TaskTracker`,
category `SpikeR1`) on every successful `SwiftDataTimerEventRepository.append(_:)`, plus an
`NSPersistentCloudKitContainer.eventChangedNotification` observer installed from
`AppDataModelContainer.makeSynced()`. Transient only — synced schema untouched. Capture method
documented in `docs/ICLOUD_SYNC.md`; hardware run still outstanding.
2026-08-14 — Signing unblocked: user's Apple Developer account approved for the paid Individual
Program (team `925WW662VY`, `MUHAMMED ELSAEED`). Added `DEVELOPMENT_TEAM` to `project.yml`;
registered this Mac's UDID via one interactive Xcode build; all three schemes now build/codesign
clean from the CLI with `-allowProvisioningUpdates`. Switched macOS and iOS app entry points from
`AppDataModelContainer.makeLocalInMemory()` to `.makeSynced()`. All 25 package tests still pass.
Next: spike R-1 on real hardware.
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

2026-08-16 — Added SwiftUI `#Preview` coverage for every view across iOS, macOS, watchOS.
Each app target has `PreviewSupport.swift` (in-memory `TaskRepository`/`TimerEventRepository`/
`TaskTimeLogRepository` doubles + `PreviewTimeSource` conforming to both TaskDomain and TimerDomain
`TimeSource`, plus a `@MainActor PreviewMocks` factory with sample tasks and idle/running/paused
timer and time-log builders) — all wrapped in `#if DEBUG`. The three shared `ViewPreviews.swift`
files were removed; every top-level app screen now carries its own inline `#Preview` next to it
(TimerTabView, TodayTabView, PoolTabView, TaskEditSheet, SettingsTabView, RootTabView on iOS;
TaskHubView, TimerSectionView, PreferencesView on macOS; WatchRootView, ActiveTimerScreen,
TodayScreen on watchOS) covering populated/empty/linked/search/completed/excluded cases. The
`AppDesign` package components (StopwatchAnalogFace, TimerControlButton, TaskCompletionMark,
TaskTimerActionBar, TimerDisplay, TimerCountdownRow, TimerInlinePauseButton, SurfaceGroup,
TimerDisplayModePager, AppTabView) got self-contained previews using literal values — they must NOT
reference app-target `PreviewMocks` (AppDesign can't import the app, and that was the source of the
"Cannot find 'PreviewMocks' in scope" error). `AppData` is an explicit dependency of the three
app targets in `project.yml`. Verified: `xcodegen generate` + Debug builds succeed for iOS, macOS,
watchOS. NOTE: macOS `TimerSectionView.init` takes only `(timer: + sizing params)`, `TaskHubView.init`
only `(today:pool:timer:)`, and `PreviewMocks.pausedTimer` uses `(duration:accumulated:)` (no
`remaining:`) — these differ from the iOS signatures.

2026-08-17 — Redesigned the iPhone Timer tab (`Apps/iOS/TimerTabView.swift`) from the old list-row +
page-swipe display into a mobile-first timer face: segmented Timer/Stopwatch mode switch, large
centered digital timer, digital-first stopwatch view, idle-only duration presets, linked-task affordance,
and bottom safe-area controls for Start/Pause/Resume/Stop/Reset. Timer arithmetic remains in
`ActiveTimerController`; the view only renders formatted labels from AppFeature. Verified: iOS, macOS,
watchOS Debug builds succeed; `Packages/AppDesign` tests pass.
2026-08-17 — Timer tab UX iteration: idle timer face now opens a task picker, users can select Today,
Pool, or No Task before starting, and `Start` links the session via `ActiveTimerController.start(duration:
relatedTaskID:)`. Active linked sessions show the task inside the timer face; paused active sessions use
the existing Resume flow for the remaining time. Bottom controls remain in a safe-area panel near the tab
bar. Verified: iOS Debug build succeeds after the change; macOS/watchOS builds and AppFeature/AppDesign
package tests passed before this cleanup in the same iteration.
2026-08-18 — Search/Add tab empty state fix: replaced native `.symbolEffect(.drawOn)` with custom
`AddTaskDrawOnIcon` (SwiftUI Path + `.trim(from:to:)` stroke animation, 0.7s easeInOut) because
the native drawOn holds the symbol undrawn after nonRepeating completion and renders nothing on the
iOS simulator at all (confirmed by probe app). Extracted `AddTaskEmptyState` view with centered layout.
Added `.ignoresSafeArea(.keyboard, edges: .bottom)` so the keyboard doesn't push content upward.
Tab bar label now uses static `Label("Add", systemImage:)` to avoid drawOn hiding unselected tab icons.
Verified: icon visible and centered on simulator after animation, all three app builds succeed. Also
fixed a pre-existing `Task.isInPool` bug (was `completedAt == nil`, now correctly
`scheduledDay == nil && completedAt == nil` per `AGENTS.md` contract), which fixed a failing
`TaskDomain` test. Updated stale `AppDesignTests` symbol expectations to match current
`AppSymbols.Navigation` values (calendar.badge.plus / rectangle.stack.badge.plus). All 30 package
tests pass.
