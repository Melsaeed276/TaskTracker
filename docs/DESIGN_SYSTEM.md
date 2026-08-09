# Design System

## Deployment Floor

The floor is **macOS 15 Sequoia · iOS 18 · watchOS 11**. Liquid Glass is conditional on 26+, not assumed. Every supported OS therefore has **two appearances to support**: the floor generation (materials) and 26+ (Liquid Glass) (plan §26, ADR 014).

| Platform | Floor (this project) | Liquid Glass release |
|---|---|---|
| macOS | 15 Sequoia | 26 Tahoe |
| iOS | 18 | 26 |
| watchOS | 11 | 26 |

Apple realigned all platform numbering on the year in 2025. There are no intermediate releases — no macOS 16–25, no iOS 19–25. macOS 15 Sequoia is the same-generation partner of iOS 18 and watchOS 11 (plan §1).

Both paths are laid out and reviewed, not just the modern one. The floor build is what most of the user's devices may actually run, so it is a first-class appearance, not a degraded mode (plan §26).

---

## Component-Level Compatibility Seam

`AppDesign` exposes semantic surfaces and resolves them internally. Feature code never writes `#available` and never names a material (plan §26).

### Why modifiers alone are insufficient

Liquid Glass differs **structurally**, not only visually. `GlassEffectContainer` groups sibling glass elements and morphs between them, toolbars gain grouping and spacer semantics, and tab bars gain minimise-on-scroll. None of that is expressible as "swap one background for another." The seam is therefore **component-shaped**: `@ViewBuilder` containers alongside modifiers (plan §26, R-6).

### The seam table

| Seam | 26+ | Floor (iOS 18 / macOS 15 / watchOS 11) |
|---|---|---|
| `.navigationSurface()` | `.glassEffect()` | `.background(.regularMaterial)` |
| `.floatingControlSurface()` | `.glassEffect(in:)` + `.interactive()` | material + subtle shadow |
| `SurfaceGroup { }` | `GlassEffectContainer { }` | passthrough container |
| `AppToolbar { }` | grouped items + `ToolbarSpacer` | conventional `ToolbarItemGroup` |
| `AppTabView { }` | `.tabBarMinimizeBehavior(.onScrollDown)` | plain `TabView` |
| `.contentScrollEdge()` | `.scrollEdgeEffectStyle(.hard, for: .top)` | no-op |

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
|---|---|---|
| `xs` | 4pt | Tight spacing, icon gaps |
| `s` | 8pt | Compact lists, inline elements |
| `m` | 16pt | Standard padding, section gaps |
| `l` | 24pt | Generous padding, card insets |
| `xl` | 32pt | Section separation |
| `xxl` | 48pt | Major layout breaks |

### Radii

| Token | Usage |
|---|---|
| Small | Inline elements, badges |
| Medium | Cards, list rows |
| Large | Sheets, panels |

### Durations

Animation durations for transitions, haptics, and motion design. Consistent across platforms.

---

## Typography

Semantic text styles only. Full Dynamic Type support across all platforms (plan §26).

| Style | Usage |
|---|---|
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
- Preferences via `Settings` scene.
- `LSUIElement` so no Dock icon appears.

### iOS — touch-first and navigational

- Tab-based navigation with `.tabViewStyle(.sidebarAdaptable)` (iOS 18 — exactly the floor).
- iPhone gets tabs; iPad gets a sidebar (plan §22).
- Generous touch targets (minimum 44pt).
- Swipe actions for quick operations (Pool→Today).
- Task editing as a sheet.
- Timer presets (15/25/30/45/60) in MVP 2.

### watchOS — glanceability with minimal transparency and high contrast

- Viewed at arm's length in sunlight — minimal transparency, high contrast (plan §26).
- Takes the tokens and the symbol catalogue but very little of the glass.
- Two screens, no deeper hierarchy (plan §23).
- Large monospaced countdown for the active timer.
- Single primary control; secondary controls behind a swipe.
- Standalone — reaches iCloud directly, no phone dependency.

---

## App Icon

Built in Icon Composer as three layers, all appearance variants reviewed, circular watchOS mask checked. Layered icons apply on 26+; a conventional icon ships for the older floor (plan §26).

---

## Cross-References

- `ARCHITECTURE.md` — package structure, why `AppDesign` imports SwiftUI only
- `TIMER_ARCHITECTURE.md` — `TimerDisplay` component (monospaced-digit countdown)
- `ICLOUD_SYNC.md` — how the design system interacts with sync status
- `TESTING.md` — accessibility verification requirements
- `ROADMAP.md` — M9 (polish), Liquid Glass audit, material-fallback verification
