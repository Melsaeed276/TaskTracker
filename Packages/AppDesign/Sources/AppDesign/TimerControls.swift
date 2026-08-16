import SwiftUI

public enum TimerUI {
    /// Shared anchor keeps TimelineView ticks aligned and stable across re-renders.
    public static let timelineAnchor = Date(timeIntervalSinceReferenceDate: 0)
}

public struct TimerControlButton: View {
    public enum Tone {
        case positive
        case caution
        case neutral

        var color: Color {
            switch self {
            case .positive: return .green
            case .caution: return .red
            case .neutral: return .primary
            }
        }
    }

    private let title: String
    private let systemImage: String
    private let tone: Tone
    private let diameter: CGFloat
    private let action: () -> Void

    public init(
        title: String,
        systemImage: String,
        tone: Tone,
        diameter: CGFloat = 84,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tone = tone
        self.diameter = diameter
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.xs) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(tone.color)
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .circularControlSurface()
    }
}

public struct TaskCompletionMark: View {
    public let isCompleted: Bool
    public let tint: Color

    public init(isCompleted: Bool, tint: Color = .accentColor) {
        self.isCompleted = isCompleted
        self.tint = tint
    }

    public var body: some View {
        ZStack {
            Circle()
                .strokeBorder(isCompleted ? tint : .secondary.opacity(0.45), lineWidth: 1.8)
            if isCompleted {
                Circle()
                    .fill(tint.opacity(0.18))
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: 24, height: 24)
        // Hollow stroke has no fill, so macOS hit-testing skips the interior without an
        // explicit content shape (same failure mode as the menu-bar Today row).
        .contentShape(Rectangle())
    }
}

/// Compact active-timer strip for app chrome — plain values only (no domain types).
public struct TaskTimerActionBar: View {
    public let countdown: String
    public let statusText: String
    public let isPaused: Bool
    public let onPauseResume: () -> Void
    public let onStop: () -> Void
    /// Opens the Timer tab. Omit when already there.
    public let onOpenTimer: (() -> Void)?
    /// Opens the linked task. Title is display-only; omit when there is no link or already in that task.
    public let relatedTaskTitle: String?
    public let onOpenRelatedTask: (() -> Void)?

    public init(
        countdown: String,
        statusText: String,
        isPaused: Bool,
        onPauseResume: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onOpenTimer: (() -> Void)? = nil,
        relatedTaskTitle: String? = nil,
        onOpenRelatedTask: (() -> Void)? = nil
    ) {
        self.countdown = countdown
        self.statusText = statusText
        self.isPaused = isPaused
        self.onPauseResume = onPauseResume
        self.onStop = onStop
        self.onOpenTimer = onOpenTimer
        self.relatedTaskTitle = relatedTaskTitle
        self.onOpenRelatedTask = onOpenRelatedTask
    }

    private var statusColor: Color {
        isPaused ? .orange : .green
    }

    public var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.s) {
            HStack(alignment: .center, spacing: AppSpacing.s) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(countdown)
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("taskTimerBar.countdown")

                    Text(statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor.opacity(0.9))
                        .textCase(.uppercase)
                        .tracking(0.4)
                        .lineLimit(1)
                }
            }
            .fixedSize(horizontal: true, vertical: true)
            .layoutPriority(1)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(statusText), \(countdown)")

            Spacer(minLength: AppSpacing.xs)

            SurfaceGroup {
                HStack(spacing: AppSpacing.s) {
                    iconControl(
                        systemImage: isPaused ? AppSymbols.Timer.resume : AppSymbols.Timer.pause,
                        foreground: isPaused ? TimerControlButton.Tone.positive.color : .primary,
                        action: onPauseResume,
                        accessibilityLabel: isPaused ? "Resume timer" : "Pause timer",
                        accessibilityIdentifier: "taskTimerBar.pauseResume"
                    )

                    iconControl(
                        systemImage: AppSymbols.Timer.stop,
                        foreground: TimerControlButton.Tone.caution.color,
                        action: onStop,
                        accessibilityLabel: "Stop timer",
                        accessibilityIdentifier: "taskTimerBar.stop"
                    )

                    if let onOpenRelatedTask, let relatedTaskTitle {
                        openTaskControl(title: relatedTaskTitle, action: onOpenRelatedTask)
                    }

                    if let onOpenTimer {
                        iconControl(
                            systemImage: AppSymbols.Navigation.timer,
                            foreground: .primary,
                            action: onOpenTimer,
                            accessibilityLabel: "Open Timer",
                            accessibilityIdentifier: "taskTimerBar.openTimer"
                        )
                    }
                }
            }
            .layoutPriority(0)
        }
        .padding(.horizontal, AppSpacing.m)
        .padding(.vertical, AppSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("taskTimerBar")
    }

    /// Prefer titled capsule; fall back to icon-only so the countdown never wraps.
    @ViewBuilder
    private func openTaskControl(title: String, action: @escaping () -> Void) -> some View {
        ViewThatFits(in: .horizontal) {
            Button(action: action) {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: AppSymbols.Navigation.taskHub)
                        .font(.subheadline.weight(.semibold))
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                .padding(.horizontal, AppSpacing.m)
                .frame(height: 40)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .floatingControlSurface()
            .accessibilityLabel("Open task \(title)")
            .accessibilityIdentifier("taskTimerBar.openTask")

            iconControl(
                systemImage: AppSymbols.Navigation.taskHub,
                foreground: .primary,
                action: action,
                accessibilityLabel: "Open task \(title)",
                accessibilityIdentifier: "taskTimerBar.openTask"
            )
        }
    }

    private func iconControl(
        systemImage: String,
        foreground: Color,
        action: @escaping () -> Void,
        accessibilityLabel: String,
        accessibilityIdentifier: String
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(foreground)
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .circularControlSurface()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
