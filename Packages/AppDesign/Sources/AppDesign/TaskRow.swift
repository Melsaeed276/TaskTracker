import SwiftUI

/// Reusable task list row. Plain values only — callers map domain data, apply
/// gestures, and attach `.swipeActions` / `.contextMenu` at the call site.
public struct TaskRow: View {
    /// Completion-mark button on the leading edge.
    public struct LeadingAction {
        public var isOn: Bool
        public var tint: Color
        public var action: () -> Void

        public init(isOn: Bool, tint: Color = .accentColor, action: @escaping () -> Void) {
            self.isOn = isOn
            self.tint = tint
            self.action = action
        }
    }

    /// Optional icon button at the row's trailing inner edge.
    public struct TrailingAction {
        public var icon: String
        public var tint: Color
        public var accessibilityLabel: String
        public var action: () -> Void

        public init(
            icon: String,
            tint: Color,
            accessibilityLabel: String,
            action: @escaping () -> Void
        ) {
            self.icon = icon
            self.tint = tint
            self.accessibilityLabel = accessibilityLabel
            self.action = action
        }
    }

    public var title: String
    public var notes: String?
    public var isCompleted: Bool
    /// Short badge rendered beside the title; nil hides it.
    public var priorityLabel: String?
    public var leading: LeadingAction?
    public var trailing: TrailingAction?
    public var onPress: (() -> Void)?
    public var completionAnimationPhaseDurationNanoseconds: UInt64

    @State private var displayedCompletionState: Bool?
    @State private var completionAnimationPhase: CompletionAnimationPhase?
    @State private var completionAnimationToken = 0

    public init(
        title: String,
        notes: String? = nil,
        isCompleted: Bool = false,
        priorityLabel: String? = nil,
        leading: LeadingAction? = nil,
        trailing: TrailingAction? = nil,
        onPress: (() -> Void)? = nil,
        completionAnimationPhaseDurationNanoseconds: UInt64 = 700_000_000
    ) {
        self.title = title
        self.notes = notes
        self.isCompleted = isCompleted
        self.priorityLabel = priorityLabel
        self.leading = leading
        self.trailing = trailing
        self.onPress = onPress
        self.completionAnimationPhaseDurationNanoseconds = completionAnimationPhaseDurationNanoseconds
    }

    public var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.s) {
            if let leading {
                Button {
                    let nextState = !completionVisualState
                    debugAnimationLog(
                        "completion button pressed; currentVisualState=\(completionVisualState), nextVisualState=\(nextState)"
                    )
                    animateCompletionChange(to: nextState, source: "button")
                    leading.action()
                } label: {
                    TaskCompletionMark(
                        isCompleted: completionVisualState,
                        tint: leading.tint,
                        animationToken: completionAnimationToken
                    )
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("taskRow.completionButton")
                .accessibilityLabel(
                    completionVisualState ? String(localized: "Mark not done") : String(localized: "Mark done")
                )
                .accessibilityValue(completionAccessibilityValue)
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.s) {
                    Text(title)
                        .font(.body)
                        .strikethrough(completionVisualState)
                        .foregroundStyle(completionVisualState ? .secondary : .primary)
                        .animation(.easeInOut(duration: 0.2), value: completionVisualState)

                    if let priorityLabel {
                        Text(priorityLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, AppSpacing.s)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }

                if let notes, !notes.isEmpty {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if let trailing {
                Button(action: trailing.action) {
                    Image(systemName: trailing.icon)
                        .font(.body)
                        .foregroundStyle(trailing.tint)
                        .padding(.trailing, AppSpacing.s)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(trailing.accessibilityLabel)
            }
        }
        .padding(.vertical, AppSpacing.xs)
        .contentShape(Rectangle())
        .onTapGesture { onPress?() }
        .onAppear {
            if displayedCompletionState == nil {
                displayedCompletionState = externalCompletionState
                completionAnimationPhase = externalCompletionState ? .completed : .incomplete
                debugAnimationLog("local completion visual state initialized to \(externalCompletionState)")
            }
        }
        .onChange(of: externalCompletionState) { oldValue, newValue in
            debugAnimationLog("external completion state changed \(oldValue) -> \(newValue)")
            guard newValue != completionVisualState else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.52)) {
                animateCompletionChange(to: newValue, source: "external")
            }
        }
        .task(id: completionAnimationToken) {
            guard completionAnimationToken > 0 else { return }
            try? await Swift.Task.sleep(nanoseconds: completionAnimationPhaseDurationNanoseconds)
            guard !Swift.Task.isCancelled else { return }
            completionAnimationPhase = completionVisualState ? .completed : .incomplete
            debugAnimationLog("completion animation phase settled to \(completionAnimationPhase?.rawValue ?? "unknown")")
        }
    }

    private var completionVisualState: Bool {
        displayedCompletionState ?? externalCompletionState
    }

    private var externalCompletionState: Bool {
        leading?.isOn ?? isCompleted
    }

    private var completionAccessibilityValue: String {
        (completionAnimationPhase ?? (completionVisualState ? .completed : .incomplete)).rawValue
    }

    private func animateCompletionChange(to nextState: Bool, source: String) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.52)) {
            displayedCompletionState = nextState
            completionAnimationPhase = nextState ? .animatingToCompleted : .animatingToIncomplete
            completionAnimationToken += 1
        }
        debugAnimationLog(
            "local completion visual state set to \(nextState); phase=\(completionAnimationPhase?.rawValue ?? "unknown"); source=\(source); token=\(completionAnimationToken)"
        )
    }

    private func debugAnimationLog(_ message: String) {
        #if DEBUG
        debugPrint("[TaskRow animation] \(message)")
        #endif
    }

    private enum CompletionAnimationPhase: String {
        case incomplete
        case completed
        case animatingToCompleted = "animating-to-completed"
        case animatingToIncomplete = "animating-to-incomplete"
    }
}

#if DEBUG

/// Hosts rows under test in a real List and echoes the most recent callback.
private struct TaskRowPreviewScaffold<Rows: View>: View {
    let rows: (Binding<String>) -> Rows
    @State private var lastAction = "Interact with the row above"

    init(@ViewBuilder rows: @escaping (Binding<String>) -> Rows) {
        self.rows = rows
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                rows($lastAction)
            }

            Divider()
            Text(lastAction)
                .font(.caption.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppSpacing.m)
                .padding(.vertical, AppSpacing.s)
                .background(.quaternary)
        }
    }
}

#Preview("TaskRow — Defaults, incomplete + completed") {
    TaskRowPreviewScaffold { _ in
        TaskRow(
            title: "Write project plan",
            notes: "Cover goals and milestones",
            leading: .init(isOn: false) {},
            onPress: {}
        )
        TaskRow(
            title: "Book dentist appointment",
            isCompleted: true,
            leading: .init(isOn: true) {}
        )
    }
}

#Preview("TaskRow — Priority + trailing action") {
    TaskRowPreviewScaffold { log in
        TaskRow(
            title: "Renew domain",
            priorityLabel: "High",
            leading: .init(isOn: false) {},
            trailing: .init(
                icon: "play.fill",
                tint: .secondary,
                accessibilityLabel: String(localized: "Start timer")
            ) {
                log.wrappedValue = "Trailing action → start timer"
            },
            onPress: { log.wrappedValue = "Pressed" }
        )
    }
}

#Preview("TaskRow — Very large title") {
    TaskRowPreviewScaffold { _ in
        TaskRow(
            title: "Prepare the quarterly roadmap review presentation slides for the leadership offsite including the revised budget appendix",
            leading: .init(isOn: false) {},
            trailing: .init(
                icon: "play.fill",
                tint: .secondary,
                accessibilityLabel: String(localized: "Start timer")
            ) {}
        )
        TaskRow(
            title: "Prepare the quarterly roadmap review presentation slides for the leadership offsite including the revised budget appendix",
            leading: .init(isOn: false) {},
            trailing: .init(
                icon: "play.fill",
                tint: .secondary,
                accessibilityLabel: String(localized: "Start timer")
            ) {}
        )
        .environment(\.dynamicTypeSize, .accessibility1)
    }
}

#Preview("TaskRow — Long content clamp") {
    TaskRowPreviewScaffold { _ in
        TaskRow(
            title: "Refactor the synchronization engine so that offline sessions converge deterministically",
            notes: "This note deliberately runs past two lines to verify the two-line clamp with longer Dynamic Type sizes.",
            leading: .init(isOn: false) {}
        )
        TaskRow(title: "Short", leading: .init(isOn: true) {})
    }
}

#endif
