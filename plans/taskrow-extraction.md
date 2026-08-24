# Plan: Extract TaskRow to AppDesign + Pool Settings

## Goal
Move `TodayTaskRow` from `Apps/iOS/TodayTabView.swift` into `Packages/AppDesign` as a reusable `TaskRow`, make it configurable with leading/trailing actions and onPress, and add pool-specific settings (completion action, trailing button visibility).

## Architecture Constraint
AppDesign imports **SwiftUI only** — no TaskDomain, no controllers. TaskRow takes plain values and closures, never `Task` or `PoolController`.

---

## Task 1: Create `TaskRow` in AppDesign

**File:** `Packages/AppDesign/Sources/AppDesign/TaskRow.swift` (new)

Public view taking plain values:
```swift
public struct TaskRow: View {
    let title: String
    let notes: String?
    let isCompleted: Bool
    let priorityLabel: String?     // nil = no badge
    let leading: LeadingAction?    // completion mark button
    let trailing: TrailingAction?  // optional trailing button
    let onPress: (() -> Void)?
}

public struct LeadingAction {
    let isOn: Bool
    let tint: Color
    let action: () -> Void
}

public struct TrailingAction {
    let icon: String
    let tint: Color
    let accessibilityLabel: String
    let action: () -> Void
}
```

Layout matches existing rows: `HStack { [leading button] [VStack(title, notes)] Spacer [trailing button?] }`
- `TaskCompletionMark` already lives in AppDesign — reuse it for the leading button
- Caller applies `.swipeActions`, `.contextMenu`, `.onTapGesture` externally

**Acceptance:**
- [ ] TaskRow compiles in AppDesign package
- [ ] Visual output matches TodayTaskRow when given same inputs

---

## Task 2: Create `PoolPreferences` in AppDesign

**File:** `Packages/AppDesign/Sources/AppDesign/PoolPreferences.swift` (new)

```swift
public enum PoolCompletionAction: String, CaseIterable, Codable {
    case completeAndArchive   // current default
    case completeOnly
    case archiveOnly
}

@Observable public final class PoolPreferences {
    @ObservationIgnored @AppStorage public var showTrailingButton: Bool = true
    @ObservationIgnored @AppStorage public var completionAction: PoolCompletionAction = .completeAndArchive
}
```

Storage keys namespaced as `pool.showTrailingButton` and `pool.completionAction`.

**Acceptance:**
- [ ] PoolPreferences readable/writable from app targets
- [ ] Defaults match current behavior (trailing button ON, action = completeAndArchive)

---

## Task 3: Update TodayTabView to use TaskRow

**File:** `Apps/iOS/TodayTabView.swift`

Replace `TodayTaskRow` private struct with `TaskRow` usage:
- `leading`: `LeadingAction(isOn: task.isCompleted, tint: .accentColor, action: { await today.complete(task) })`
- `trailing`: nil (Today has no trailing button)
- `onPress`: `{ editingTask = task }`
- Apply `.swipeActions` and `.contextMenu` at call site (unchanged)
- Delete the private `TodayTaskRow` struct

**Acceptance:**
- [ ] Today tab visually identical
- [ ] All swipe actions and context menu still work

---

## Task 4: Update PoolTabView to use TaskRow + PoolPreferences

**File:** `Apps/iOS/PoolTabView.swift`

Replace inline `poolRow` content with `TaskRow`:
- `leading`: completion mark action derived from `PoolPreferences.completionAction`
- `trailing`: conditional on `PoolPreferences.showTrailingButton` + `pool.needsTodayAction(for: task)`
- `onPress`: `{ editingTask = task }`
- Apply `.swipeActions`, `.contextMenu` at call site (unchanged)
- Inject `PoolPreferences` as `@State` at `PoolTabView` init

**Acceptance:**
- [ ] Pool tab visually identical with default settings
- [ ] Toggling showTrailingButton hides/shows the "Add to Today" button
- [ ] Changing completionAction changes what the leading button does

---

## Task 5: Expose pool settings in SettingsTabView

**File:** `Apps/iOS/SettingsTabView.swift`

Add a "Pool" section after Appearance:
- Picker for completion action (Bound to PoolPreferences)
- Toggle for trailing button visibility

**Acceptance:**
- [ ] Settings tab shows Pool section with two controls
- [ ] Changes take effect immediately in Pool tab

---

## Checkpoint: After all tasks
- [ ] `xcrun xcodebuild` succeeds for iOS target with zero errors
- [ ] Today tab unchanged visually
- [ ] Pool tab unchanged visually with defaults
- [ ] Pool settings toggle trailing button and completion action
- [ ] No domain types leaked into AppDesign
