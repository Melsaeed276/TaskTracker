# Design System

## Deployment Floor

The floor is **macOS 14 Sonoma · iOS 17 · watchOS 10** (ADR 014, Revision 2 — reverted from an
earlier 26-everywhere floor to keep the real iPhone 11, hardware-capped at iOS 18.6.2, usable as a
test device; kept one generation below that device's ceiling for headroom, not pinned exactly to
it). Liquid Glass is conditional on 26+, not assumed. Every supported OS therefore has **two
appearances to support**: the floor generation (materials) and 26+ (Liquid Glass) (plan §26, ADR 014).

| Platform | Floor (this project) | Liquid Glass release |
| --- | --- | --- |
| macOS | 14 Sonoma | 26 Tahoe |
| iOS | 17 | 26 |
| watchOS | 10 | 26 |

Apple realigned all platform numbering on the year starting with the 26 generation (2025). Below
that, macOS 14/iOS 17/watchOS 10 do not share a release year — they are simply each platform's
minimum version that keeps the full real-device roster (including the iPhone 11) usable (plan §1,
ADR 014 Revision 2).

Both paths are laid out and reviewed, not just the modern one. The floor build is what most of the user's devices may actually run, so it is a first-class appearance, not a degraded mode (plan §26).

---

## Component-Level Compatibility Seam

`AppDesign` exposes semantic surfaces and resolves them internally. Feature code never writes `#available` and never names a material (plan §26).

### Why modifiers alone are insufficient

Liquid Glass differs **structurally**, not only visually. `GlassEffectContainer` groups sibling glass elements and morphs between them, toolbars gain grouping and spacer semantics, and tab bars gain minimise-on-scroll. None of that is expressible as "swap one background for another." The seam is therefore **component-shaped**: `@ViewBuilder` containers alongside modifiers (plan §26, R-6).

### The seam table

| Seam | 26+ | Floor (iOS 17 / macOS 14 / watchOS 10) |
| --- | --- | --- |
| `.navigationSurface()` | `.glassEffect(.regular, in: RoundedRectangle…)` | shaped `.regularMaterial` |
| `.panelChromeSurface()` | same shaped Regular glass as navigation (no clear window fill — that broke MenuBarExtra hit-testing) | shaped `.regularMaterial` |
| `.floatingControlSurface()` | `.glassEffect(.regular.interactive(), in: Capsule())` | material + subtle shadow |
| `SurfaceGroup { }` | `GlassEffectContainer { }` | passthrough container |
| `AppToolbar { }` | grouped items + `ToolbarSpacer` | conventional `ToolbarItemGroup` |
| `AppTabView { }` | `.tabViewStyle(.sidebarAdaptable)` + `.tabBarMinimizeBehavior(.onScrollDown)` | iOS 18–25: `.tabViewStyle(.sidebarAdaptable)`, no minimize. iOS 17 (true floor): plain `TabView` |
| `.contentScrollEdge()` | `.scrollEdgeEffectStyle(.hard, for: .top)` | no-op |

**`AppTabView` is a three-way seam, not two-way** — `.tabViewStyle(.sidebarAdaptable)` (iPhone tabs,
iPad sidebar) itself requires iOS 18, one version above the iOS 17 floor (ADR 014 Revision 2). Below
iOS 18 it degrades further to a plain `TabView` (iPhone gets a conventional tab bar, no iPad
sidebar). Feature code still only ever calls `AppTabView { }` — never an `#available` check of its
own — the component internally nests the iOS-18 check inside the 26+ check.

This confines the entire dual-appearance problem to one package, keeps the branching out of every feature, and makes deleting the fallback when the floor eventually rises a single-package change (plan §26).

---

## Liquid Glass Rules (26+)

### Navigation layer only

Glass belongs to the **navigation layer** only. Task rows and list content get **no glass** — glass on the content layer competes with navigation and reads as noise (plan §26).

### Regular variant only

Regular variant everywhere. The **Clear variant is banned** outright. Clear requires:

1. Media-rich content
2. An acceptable dimming layer
3. Bold bright foreground content

This app satisfies none of the three, so Clear is not left to taste — it is banned (plan §26).

### Tint the single primary action

`.tint()` reserved for the single primary action in a context — the timer's primary control. Not for decorative purposes, not for multiple elements (plan §26).

### No custom backgrounds

No custom backgrounds on toolbars or navigation. No `.presentationBackground` on sheets. No `UIVisualEffectView`/`NSVisualEffectView`. No hard-coded row heights or control frames (plan §26).

### Adjacent glass controls

Adjacent glass controls go inside a `GlassEffectContainer`. Default stack spacing, never tightened (plan §26).

---

## Tokens

### Spacing

Consistent spacing tokens used across all platforms and components. Defined as constants in `AppDesign`:

| Token | Value | Usage |
| --- | --- | --- |
| `xs` | 4pt | Tight spacing, icon gaps |
| `s` | 8pt | Compact lists, inline elements |
| `m` | 16pt | Standard padding, section gaps |
| `l` | 24pt | Generous padding, card insets |
| `xl` | 32pt | Section separation |
| `xxl` | 48pt | Major layout breaks |

### Radii

| Token | Usage |
| --- | --- |
| Small | Inline elements, badges |
| Medium | Cards, list rows |
| Large | Sheets, panels |

### Durations

Animation durations for transitions, haptics, and motion design. Consistent across platforms.

---

## Typography

Semantic text styles only. Full Dynamic Type support across all platforms (plan §26).

| Style | Usage |
| --- | --- |
| `headlineLarge` | Page titles |
| `headlineMedium` | Section headers |
| `titleLarge` | Card titles |
| `titleMedium` | List item titles |
| `bodyLarge` | Primary body text |
| `bodyMedium` | Secondary body text |
| `labelLarge` | Buttons, primary labels |
| `labelMedium` | Tertiary labels, captions |

### Monospaced digit rendering

Timer displays use monospaced-digit rendering so digits do not shift as values change. This is handled by `TimerDisplay` in `AppDesign` (plan §26).

### Dynamic Type

All text uses semantic styles from the theme, which automatically scale with the user's Dynamic Type preference. No hardcoded font sizes anywhere in the codebase.

---

## SF Symbols Catalogue

`AppSymbols` is a single catalogue of SF Symbols used across all three apps. This prevents drift — three apps cannot disagree on which symbol represents which concept (plan §26).

### Catalogue structure

- One file per feature area (timer, tasks, navigation, status)
- Named constants, not string literals
- Fallback symbols for older OS versions where needed
- Review at each milestone for new symbols available in newer SDKs

---

## Motion

### Animation principles

- Transitions are subtle and functional — they communicate state changes, not decorate.
- Timer countdown uses `TimelineView` at 1 Hz — no animation for the countdown itself; the view re-derives from timestamps every tick (plan §17, §19).
- Haptic feedback on key actions (start, stop, complete) where platform-appropriate.

### Reduce Motion

All motion respects the `UIAccessibility.isReduceMotionEnabled` / `NSWorkspace.accessibilityDisplayShouldReduceMotion` setting. When Reduce Motion is active:

- No cross-fade transitions — use instant state changes
- No parallax effects
- No spring animations — use linear or ease-in-out
- The timer countdown itself is unaffected (it is informational, not decorative motion)

Liquid Glass on 26+ honours Reduce Motion automatically, provided we have not overridden it. The material fallback on the floor must also respect it (plan §26).

---

## Accessibility

Accessibility is not a later pass. It is built into the design system from the start (plan §26).

### Reduce Transparency

Both appearance paths must work under Reduce Transparency:

- **26+ path:** Liquid Glass honours Reduce Transparency automatically. Glass effects are replaced with opaque materials. This is handled by the system — we must not override it.
- **Floor path:** Material backgrounds already provide opaque surfaces. `.background(.regularMaterial)` degrades gracefully under Reduce Transparency.

### Increase Contrast

Under Increase Contrast:

- Borders and dividers become more prominent
- Text contrast ratios increase
- Control states (enabled/disabled) are more visually distinct
- Both appearance paths must support this — the material fallback must be verified under Increase Contrast

### Reduce Motion

As described in the Motion section above. Both paths respect this setting.

### VoiceOver

Every icon-only control must have a VoiceOver label. All interactive elements must be accessible. This is verified at each milestone (plan §26).

### Dynamic Type

Full Dynamic Type support. All text uses semantic styles that scale automatically. No hardcoded font sizes. Layouts adapt to larger text sizes without clipping or overlap.

---

## Per-Platform Divergence

Platform divergence is intentional. Shared domain, shared design tokens — not shared layouts (plan §2, §26).

### macOS — dense and keyboard-first

- Menu bar is the primary surface — interaction budget is a fraction of a second (plan §2, §21).
- Keyboard shortcuts for all primary actions.
- Dense information layout — more content per square pixel.
- `MenuBarExtra(.window)` with panel-style interaction.
- Menu-bar panel uses a segmented **Today / Timer** control so only one surface is visible at a
  time; the Open Tasks / Preferences action row stays pinned below the tab content. Default tab is
  Today; if a timer is already active when the panel appears, Timer is shown once (not re-forced
  after a manual switch in the same open session).
- Today rows: circle completes/uncompletes; title opens the inline details editor; trailing
  **Run** (`.borderedProminent`) starts a focus timer for that task and switches to the Timer tab.
  Run / Start Timer from a task remain enabled while another session is active — starting
  supersedes the current session (see `docs/TIMER_ARCHITECTURE.md`). To **continue** the same
  session after a break, use **Pause** then **Resume** on the Timer tab; **Stop** ends it
  permanently and cannot be continued.
- Preferences via `Settings` scene.
- `LSUIElement` so no Dock icon appears.

The idle menu-bar glyph is an exact monochrome template rendering of the app icon's vector
composition: its crown, open stopwatch ring, four cardinal markers, and rounded completion check.
Its source is
[`Design/MenuBarIcon/TaskTrackerMenuBarGlyph.svg`](../Design/MenuBarIcon/TaskTrackerMenuBarGlyph.svg).
`MenuBarStatusIcon` rasterizes those paths once into an 18 pt native `NSImage` template, preserving
automatic system menu-bar tinting and reliable `MenuBarExtra` rendering without a bitmap export.

### iOS — touch-first and navigational

- Tab-based navigation via `AppTabView { }` (see the seam table above). `.tabViewStyle(.sidebarAdaptable)`
  applies from iOS 18; the true floor (iOS 17, ADR 014 Revision 2) falls back to a plain `TabView`.
- iPhone gets tabs; iPad gets a sidebar, from iOS 18 (plan §22).
- Generous touch targets (minimum 44pt).
- Swipe actions for quick operations (Pool→Today).
- Today and Pool use a shared bottom quick-entry control instead of an inline list row. It sits in the
  bottom safe area above the tab bar, rises above the keyboard when focused, and shows existing-task
  suggestions above the field like iPhone Spotlight. This keeps capture thumb-reachable while preserving
  the task list as content.
- Task editing as a sheet (title, notes, scheduled day, priority, start-timer-for-task, **Time Spent**
  log with total / add-edit-delete adjustments / hide session from total, full-width Save + Delete).
  Completing a Today task removes it from the Today list immediately; reopen from Pool → Completed.
  Pool supports Active / Completed show modes and sort (newest, oldest, title, priority).
  The active timer strip is **app-wide** (bottom safe-area inset on Today / Pool / Settings content —
  above the tab bar, never over it): countdown, pause/resume, stop, jump to Timer, and jump to the
  linked task when `relatedTaskID` is set. Hidden on the Timer tab (full controls live there). While
  the linked task’s edit sheet is open, the same strip appears **inside the sheet** without the Open
  Task control (already on that task).
- The iPhone Timer tab is a fixed, non-scrolling control surface. The large time face owns the upper
  content area; setup and actions live in the lower thumb zone near the tab bar.
- Timer setup is bottom-first: when idle in Timer mode, a compact setup dock sits directly above the
  action row with **Choose task / selected task** and timer presets (15/25/30/45/60). Start links the
  session to the selected task via `relatedTaskID`; **No task** remains available for standalone focus.
- Active timer controls are one row in the bottom dock: primary Pause/Resume, compact Stop, and compact
  Reset. Buttons use tinted backgrounds and a pressed scale/opacity animation, not `navigationSurface()`
  or floating glass backgrounds. The dock is visually close to, but not replacing, the native tab bar.
- Active linked sessions show the linked task in the bottom dock above the action row; tapping opens the
  task on Today or Pool when available. A paused active session resumes the remaining time; stopped
  sessions are not revived.
- Live Activities for the active timer (**iOS/iPadOS only** — ActivityKit has no macOS authoring
  surface; a Mac may *mirror* an iPhone Live Activity via Continuity, but apps cannot start one on
  macOS). On Mac, the equivalent glance is the **menu-bar status item**: app icon when idle,
  monospaced remaining countdown when active. iOS Live Activities use fire-date based countdown;
  remaining seconds are never stored or synced. Requires Live Activities enabled for the app in
  Settings, and a device/simulator that supports them. Tapping a Live Activity opens
  `tasktracker://timer` and selects the Timer tab; starting a timer from a task sheet does the same.

### watchOS — glanceability with minimal transparency and high contrast

- Viewed at arm's length in sunlight — minimal transparency, high contrast (plan §26).
- Takes the tokens and the symbol catalogue but very little of the glass.
- Two screens, no deeper hierarchy (plan §23).
- Large monospaced countdown for the active timer.
- Single primary control; secondary controls behind a swipe.
- Standalone — reaches iCloud directly, no phone dependency.

---

## Timer Dual Display Modes

The Timer surface presents two presentation modes over the **same** `ActiveTimerController` state —
the domain still has one countdown session and no independent count-up timer. The mode switch is
presentation-only; timer arithmetic, remaining time, elapsed time, fire dates, pause, resume, stop,
and reset remain in AppFeature/TimerDomain.

| Mode | iPhone style | Primary readout |
|---|---|---|
| **Timer** | Large fixed digital face + bottom setup/action dock | Remaining time, preset duration label (`25 min` / `3 hr`), and idle/active status |
| **Stopwatch** | Square rounded digital panel | Elapsed `MM:SS.cs`; tapping the panel triggers the same primary Start/Pause/Resume action as the bottom button |

macOS and watchOS may still use their compact/shared components (`TimerCountdownRow`,
`StopwatchAnalogFace`, or `TimerDisplayModePager`) where those fit the available surface better. The
iPhone layout intentionally diverges because it optimizes for one-handed setup and bottom-reachable
actions.

### Color semantics

- **Elapsed** stopwatch readout uses monospaced digits and a subdued square panel so Stopwatch mode is
  visually distinct from Timer mode without introducing a separate timing model.
- **Finish time** (`endTimeText`) remains available to shared stopwatch components, but the iPhone
  Stopwatch mode hides it to keep the square panel focused on elapsed time.
- The inline pause button ring is `.orange` (`timerPauseRingColor`) with an SF Symbol, so the state is
  conveyed by icon + label, never color alone.

### Platform sizing

- **iPhone** — fixed non-scrolling Timer tab; countdown headline 64 pt; Stopwatch mode uses a square
  rounded digital panel rather than the shared analog dial.
- **macOS Task Hub pane** — dial `maxDiameter` 280.
- **macOS menu-bar panel** — list-row timer page **only** (the dial is too small to be useful there);
  `showsStopwatch: false` on `TimerSectionView`.
- **watchOS** — dial `maxDiameter` 140; sub-dial numerals drop to 10/20/30; the analog/digital tick
  runs at **1 Hz** (not 10 Hz) to save battery — centiseconds render but advance once per second.

### Accessibility and motion

- Countdown headline uses `@ScaledMetric(relativeTo: .largeTitle)` plus `minimumScaleFactor` so it grows
  with Dynamic Type and still fits narrow widths (menu-bar panel, watch).
- The inline pause button is 48 pt (≥ the 44 pt floor) and is a **separate** accessibility element, not
  combined into the row.
- No hand animation beyond `TimelineView` ticks — Reduce Motion is honoured automatically.
- VoiceOver labels: timer page reads `"Timer, <remaining> remaining"`; stopwatch page reads
  `"Stopwatch, elapsed <MM:SS.cs>"`. The task selector exposes whether a selected task will be linked
  before Start.
- Identifiers: iPhone uses `timer.display`, `timer.stopwatchDigital`, `timer.focusTarget`,
  `timer.primaryAction`, `timer.stop`, and `timer.reset`. Shared compact components still expose
  `timer.inlinePause`, `timer.stopwatchDial`, and (macOS pager dots) `timer.pageDot.timer` /
  `timer.pageDot.stopwatch`. Container identifiers are deliberately **not** applied to pager pages or
  countdown rows — a `.accessibilityIdentifier` on a non-element container propagates to every
  descendant and clobbers their individual identifiers (verified via the XCUITest accessibility tree).

---

## App Icon

The editable source of truth is [`Design/AppIcon/AppIcon.icon`](../Design/AppIcon/AppIcon.icon), built
in Apple Icon Composer. It is intentionally layered rather than a flattened export:

- **Background:** Icon Composer's native deep-sapphire foundation with a restrained blue lift,
  keeping the foreground cool and legible. Dark and Mono variants are supplied by the composer.
- **Timer System group:** independent timer ring, crown, four cardinal clock markers, and
  checkmark. The crown uses one low-profile pill that rests directly on the ring; no separate
  collar or decorative seam competes with the stopwatch silhouette. The symbol means focused time
  plus completed work. The ring keeps its existing geometry while transitioning from deep sapphire
  at the lower-left through blue into soft cyan at the upper-right.
- **Material:** Icon Composer retains the native translucent group, shadow, and crown material.
  Glass effects are deliberately disabled for the ring, checkmark, and markers, preventing
  refraction lines from crossing the primary symbol. The role of material is shallow depth—not
  glow, distortion, or a competing visual subject.

The vector construction artwork lives in [`Design/AppIcon/Source/`](../Design/AppIcon/Source/), so
the Icon Composer file remains editable without rebuilding a single bitmap. Default, Dark, Mono,
iOS/macOS, and circular watchOS previews were reviewed in Icon Composer. The primary silhouette is
the open stopwatch ring and a slightly compacted, optically raised rounded checkmark; the four markers intentionally remain
secondary at small sizes.

The document is not yet wired into an Xcode asset catalogue. The same source is intended for all
three applications, but that target-level integration should be made together when the app-icon
configuration is implemented, rather than guessing which target's asset catalogue takes ownership.
Layered icons apply on 26+; a conventional icon ships for the older floor (plan §26).

---

## Cross-References

- `ARCHITECTURE.md` — package structure, why `AppDesign` imports SwiftUI only
- `TIMER_ARCHITECTURE.md` — `TimerDisplay` component (monospaced-digit countdown)
- `ICLOUD_SYNC.md` — how the design system interacts with sync status
- `TESTING.md` — accessibility verification requirements
- `ROADMAP.md` — M9 (polish), Liquid Glass audit, material-fallback verification
