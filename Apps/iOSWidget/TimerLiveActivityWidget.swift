import ActivityKit
import SwiftUI
import WidgetKit

@main
struct TaskTrackerWidgets: WidgetBundle {
    var body: some Widget {
        TimerLiveActivityWidget()
    }
}

struct TimerLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerLiveActivityAttributes.self) { context in
            lockScreenView(context: context)
                .padding()
                .activityBackgroundTint(Color.black.opacity(0.35))
                .widgetURL(TaskTrackerDeepLink.timer)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context: context)
                        .font(.title2.monospacedDigit().weight(.semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    // Expanded Island uses Link; compact/minimal/lock use widgetURL.
                    Link(destination: TaskTrackerDeepLink.timer) {
                        Text(context.state.isPaused ? "Paused · Open Timer" : "Running · Open Timer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } compactLeading: {
                Image(systemName: "timer")
            } compactTrailing: {
                countdown(context: context)
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 40, alignment: .trailing)
            } minimal: {
                Image(systemName: "timer")
            }
            .widgetURL(TaskTrackerDeepLink.timer)
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<TimerLiveActivityAttributes>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.title)
                    .font(.headline)
                Text(context.state.isPaused ? "Paused" : "Focus timer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            countdown(context: context)
                .font(.largeTitle.monospacedDigit().weight(.semibold))
        }
    }

    @ViewBuilder
    private func countdown(context: ActivityViewContext<TimerLiveActivityAttributes>) -> some View {
        if context.state.isPaused {
            Text("Paused")
        } else if let fireDate = context.state.fireDate {
            Text(timerInterval: Date.now...fireDate, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        } else {
            Text("0:00")
                .monospacedDigit()
        }
    }
}
