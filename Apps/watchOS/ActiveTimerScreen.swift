import SwiftUI
import AppDesign
import AppFeature

struct ActiveTimerScreen: View {
    let timer: ActiveTimerController

    var body: some View {
        VStack(spacing: AppSpacing.m) {
            TimerDisplayModePager {
                TimelineView(.periodic(from: TimerUI.timelineAnchor, by: 1)) { context in
                    TimerCountdownRow(
                        remainingText: timer.remainingListLabel(at: context.date) ?? "25:00",
                        durationText: timer.sessionDurationLabel ?? "25 min",
                        isActive: timer.isActive,
                        isPaused: timer.isPaused,
                        fontSize: 30,
                        onPauseResume: {
                            Task { await performPrimaryAction() }
                        }
                    )
                }
            } stopwatchPage: {
                // 1 Hz on watchOS to save battery: the analog hands and digital readout still
                // render, but centiseconds only advance once per second instead of 10 Hz.
                TimelineView(.periodic(from: TimerUI.timelineAnchor, by: 1)) { context in
                    StopwatchAnalogFace(
                        elapsedText: timer.elapsedStopwatchDigital(at: context.date),
                        endTimeText: timer.endTimeLabel(at: context.date),
                        secondsAngle: timer.stopwatchHandAngles(at: context.date).seconds,
                        minutesAngle: timer.stopwatchHandAngles(at: context.date).minutes,
                        maxDiameter: 140
                    )
                }
            }

            if !timer.isActive {
                TimerControlButton(
                    title: String(localized: "Start"),
                    systemImage: AppSymbols.Timer.resume,
                    tone: .positive,
                    diameter: 78
                ) {
                    Task { await performPrimaryAction() }
                }
                .accessibilityLabel(String(localized: "Start timer"))
            } else {
                HStack(spacing: AppSpacing.s) {
                    TimerControlButton(
                        title: timer.isPaused ? String(localized: "Resume") : String(localized: "Pause"),
                        systemImage: primarySymbol,
                        tone: timer.isPaused ? .positive : .neutral,
                        diameter: 66
                    ) {
                        Task { await performPrimaryAction() }
                    }
                    .accessibilityLabel(primaryLabel)

                    TimerControlButton(
                        title: String(localized: "Stop"),
                        systemImage: AppSymbols.Timer.stop,
                        tone: .caution,
                        diameter: 66
                    ) {
                        Task {
                            await timer.stop()
                            await timer.reload()
                        }
                    }
                    .accessibilityLabel(String(localized: "Stop timer"))
                }
            }
        }
        .padding(.horizontal, AppSpacing.s)
        .task { await timer.reload() }
    }

    private var primaryLabel: String {
        if !timer.isActive { return String(localized: "Start") }
        return timer.isPaused ? String(localized: "Resume") : String(localized: "Pause")
    }

    private var primarySymbol: String {
        if !timer.isActive { return AppSymbols.Timer.resume }
        return timer.isPaused ? AppSymbols.Timer.resume : AppSymbols.Timer.pause
    }

    private func performPrimaryAction() async {
        if !timer.isActive {
            await timer.start()
            await timer.reload()
            return
        }

        if timer.isPaused {
            await timer.resume()
        } else {
            await timer.pause()
        }
        await timer.reload()
    }
}
#if DEBUG
#Preview("Active Timer — Running") {
    let timer = PreviewMocks.runningTimer()
    ActiveTimerScreen(timer: timer)
        .task { await timer.reload() }
}

#Preview("Active Timer — Paused") {
    let timer = PreviewMocks.pausedTimer()
    ActiveTimerScreen(timer: timer)
        .task { await timer.reload() }
}

#Preview("Active Timer — Idle") {
    ActiveTimerScreen(timer: PreviewMocks.idleTimer())
}
#endif
