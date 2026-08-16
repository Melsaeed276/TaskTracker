import SwiftUI

public struct TimerDisplayModePager<TimerPage: View, StopwatchPage: View>: View {
    @SceneStorage("timerDisplayPage") private var selectedPage = 0

    private let timerPage: TimerPage
    private let stopwatchPage: StopwatchPage

    public init(
        @ViewBuilder timerPage: () -> TimerPage,
        @ViewBuilder stopwatchPage: () -> StopwatchPage
    ) {
        self.timerPage = timerPage()
        self.stopwatchPage = stopwatchPage()
    }

    public var body: some View {
        #if os(macOS)
        VStack(spacing: AppSpacing.s) {
            ZStack {
                if selectedPage == 0 {
                    timerPage
                } else {
                    stopwatchPage
                }
            }

            HStack(spacing: AppSpacing.s) {
                pageDot(index: 0, label: "Show timer", identifier: "timer.pageDot.timer")
                pageDot(index: 1, label: "Show stopwatch", identifier: "timer.pageDot.stopwatch")
            }
        }
        .accessibilityElement(children: .contain)
        #else
        TabView(selection: $selectedPage) {
            timerPage
                .tag(0)

            stopwatchPage
                .tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .accessibilityElement(children: .contain)
        #endif
    }

    private func pageDot(index: Int, label: String, identifier: String) -> some View {
        Button {
            selectedPage = index
        } label: {
            Circle()
                .fill(selectedPage == index ? Color.primary : Color.secondary.opacity(0.35))
                .frame(width: 7, height: 7)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
