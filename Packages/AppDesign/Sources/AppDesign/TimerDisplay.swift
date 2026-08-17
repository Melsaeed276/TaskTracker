import SwiftUI

/// Monospaced-digit timer text. Pass an already-formatted string from AppFeature - no arithmetic here.
public struct TimerDisplay: View {
    public let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.body.monospacedDigit())
    }
}
#if DEBUG
#Preview("Timer Display") {
    VStack(spacing: AppSpacing.m) {
        TimerDisplay(text: "24:13")
        TimerDisplay(text: "01:05:00")
    }
    .padding()
}
#endif
