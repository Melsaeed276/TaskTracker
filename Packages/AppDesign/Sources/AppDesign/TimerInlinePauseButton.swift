import SwiftUI

public struct TimerInlinePauseButton: View {
    public let isPaused: Bool
    public let diameter: CGFloat
    public let action: () -> Void

    public init(isPaused: Bool, diameter: CGFloat = 48, action: @escaping () -> Void) {
        self.isPaused = isPaused
        self.diameter = diameter
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: isPaused ? AppSymbols.Timer.resume : AppSymbols.Timer.pause)
                .font(.body.weight(.semibold))
                .foregroundStyle(TimerDisplayTokens.timerPauseRingColor)
                .frame(width: diameter, height: diameter)
                .overlay {
                    Circle()
                        .strokeBorder(TimerDisplayTokens.timerPauseRingColor, lineWidth: 1.5)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPaused ? "Resume timer" : "Pause timer")
        .accessibilityIdentifier("timer.inlinePause")
    }
}
#if DEBUG
#Preview("Inline Pause - Running") {
    TimerInlinePauseButton(isPaused: false, action: {})
}

#Preview("Inline Pause - Paused") {
    TimerInlinePauseButton(isPaused: true, action: {})
}
#endif
