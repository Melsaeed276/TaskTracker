import SwiftUI

public struct TimerCountdownRow: View {
    public let remainingText: String
    public let durationText: String
    public let isActive: Bool
    public let isPaused: Bool
    public let onPauseResume: () -> Void

    /// Base display size, scaled with Dynamic Type relative to `.largeTitle` so the
    /// headline grows with the user's text-size preference instead of only shrinking.
    @ScaledMetric(relativeTo: .largeTitle) private var baseSize: CGFloat = 64

    public init(
        remainingText: String,
        durationText: String,
        isActive: Bool,
        isPaused: Bool,
        fontSize: CGFloat = 64,
        onPauseResume: @escaping () -> Void
    ) {
        self.remainingText = remainingText
        self.durationText = durationText
        self.isActive = isActive
        self.isPaused = isPaused
        self._baseSize = ScaledMetric(wrappedValue: fontSize, relativeTo: .largeTitle)
        self.onPauseResume = onPauseResume
    }

    public var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .center, spacing: AppSpacing.m) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    ViewThatFits(in: .horizontal) {
                        Text(remainingText)
                            .font(TimerDisplayTokens.timerListRemainingFont(size: baseSize))
                        Text(remainingText)
                            .font(TimerDisplayTokens.timerListRemainingFont(size: max(38, baseSize * 0.76)))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .foregroundStyle(isActive ? Color.primary : Color.secondary.opacity(0.45))
                    .contentTransition(.numericText())
                    .accessibilityLabel("\(durationText) timer, \(remainingText) remaining")
                    .accessibilityIdentifier("timer.display")

                    Text(durationText)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .layoutPriority(1)

                Spacer(minLength: AppSpacing.s)

                if isActive {
                    TimerInlinePauseButton(isPaused: isPaused, action: onPauseResume)
                }
            }
            .padding(.vertical, AppSpacing.m)
            Divider()
        }
    }
}
