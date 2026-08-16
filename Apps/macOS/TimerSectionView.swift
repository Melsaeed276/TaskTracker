import SwiftUI
import AppDesign
import AppFeature

struct TimerSectionView: View {
    let timer: ActiveTimerController
    let controlDiameter: CGFloat
    let displayFontSize: CGFloat
    let useKeyboardShortcuts: Bool
    let dialDiameter: CGFloat
    let showsStopwatch: Bool

    /// Inline confirm avoids `confirmationDialog`, which often fails to present from
    /// `MenuBarExtra(.window)` (Reset looked dead even when Stop worked).
    @State private var isConfirmingReset = false

    init(
        timer: ActiveTimerController,
        controlDiameter: CGFloat = 62,
        displayFontSize: CGFloat = 42,
        useKeyboardShortcuts: Bool = false,
        dialDiameter: CGFloat = 280,
        showsStopwatch: Bool = true
    ) {
        self.timer = timer
        self.controlDiameter = controlDiameter
        self.displayFontSize = displayFontSize
        self.useKeyboardShortcuts = useKeyboardShortcuts
        self.dialDiameter = dialDiameter
        self.showsStopwatch = showsStopwatch
    }

    var body: some View {
        VStack(spacing: AppSpacing.l) {
            displayPager

            SurfaceGroup {
                HStack(spacing: AppSpacing.s) {
                    startButton
                    pauseResumeButton
                    stopButton
                }
                .frame(maxWidth: .infinity)
            }

            if isConfirmingReset {
                VStack(alignment: .leading, spacing: AppSpacing.s) {
                    Text("Discard this session? Elapsed time will not be kept. Stop keeps it instead.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: AppSpacing.s) {
                        Button("Cancel") {
                            isConfirmingReset = false
                        }
                        .accessibilityIdentifier("timer.resetCancelButton")
                        Button("Discard", role: .destructive) {
                            isConfirmingReset = false
                            Swift.Task { await timer.reset() }
                        }
                        .accessibilityIdentifier("timer.resetConfirmButton")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("timer.resetConfirmPanel")
            } else {
                Button("Reset", role: .destructive) {
                    isConfirmingReset = true
                }
                .font(.callout)
                .disabled(!timer.isActive)
                .accessibilityLabel("Reset timer")
                .accessibilityIdentifier("timer.resetButton")
            }

            if timer.isActive {
                Text(
                    timer.isPaused
                        ? "Paused — Resume continues this session. Stop ends it permanently."
                        : "Pause to take a break without ending the session. Stop ends it permanently."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: timer.isActive) { _, isActive in
            if !isActive {
                isConfirmingReset = false
            }
        }
    }

    @ViewBuilder
    private var displayPager: some View {
        if showsStopwatch {
            TimerDisplayModePager {
                timerPage
            } stopwatchPage: {
                stopwatchPageContent
            }
        } else {
            timerPage
        }
    }

    private var timerPage: some View {
        TimelineView(.periodic(from: TimerUI.timelineAnchor, by: 1)) { context in
            TimerCountdownRow(
                remainingText: timer.remainingListLabel(at: context.date) ?? "25:00",
                durationText: timer.sessionDurationLabel ?? "25 min",
                isActive: timer.isActive,
                isPaused: timer.isPaused,
                fontSize: displayFontSize,
                onPauseResume: {
                    Swift.Task { await togglePauseResume() }
                }
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var stopwatchPageContent: some View {
        TimelineView(.periodic(from: TimerUI.timelineAnchor, by: 0.1)) { context in
            StopwatchAnalogFace(
                elapsedText: timer.elapsedStopwatchDigital(at: context.date),
                endTimeText: timer.endTimeLabel(at: context.date),
                secondsAngle: timer.stopwatchHandAngles(at: context.date).seconds,
                minutesAngle: timer.stopwatchHandAngles(at: context.date).minutes,
                maxDiameter: dialDiameter
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func togglePauseResume() async {
        if timer.isPaused {
            await timer.resume()
        } else {
            await timer.pause()
        }
    }

    private var startButton: some View {
        TimerControlButton(
            title: "Start",
            systemImage: AppSymbols.Timer.resume,
            tone: .positive,
            diameter: controlDiameter
        ) {
            Swift.Task { await timer.start() }
        }
        .modifier(OptionalKeyboardShortcut(
            key: "s",
            modifiers: [.command],
            isEnabled: useKeyboardShortcuts
        ))
        .accessibilityLabel("Start timer")
        .disabled(timer.isActive)
    }

    private var pauseResumeButton: some View {
        TimerControlButton(
            title: timer.isPaused ? "Resume" : "Pause",
            systemImage: timer.isPaused ? AppSymbols.Timer.resume : AppSymbols.Timer.pause,
            tone: .neutral,
            diameter: controlDiameter
        ) {
            Swift.Task {
                if timer.isPaused {
                    await timer.resume()
                } else {
                    await timer.pause()
                }
            }
        }
        .modifier(OptionalKeyboardShortcut(
            key: "p",
            modifiers: [.command],
            isEnabled: useKeyboardShortcuts
        ))
        .accessibilityLabel(timer.isPaused ? "Resume timer" : "Pause timer")
        .disabled(!timer.isActive)
    }

    private var stopButton: some View {
        TimerControlButton(
            title: "Stop",
            systemImage: AppSymbols.Timer.stop,
            tone: .caution,
            diameter: controlDiameter
        ) {
            Swift.Task { await timer.stop() }
        }
        .modifier(OptionalKeyboardShortcut(
            key: ".",
            modifiers: [.command],
            isEnabled: useKeyboardShortcuts
        ))
        .accessibilityLabel("Stop timer")
        .disabled(!timer.isActive)
    }
}

private struct OptionalKeyboardShortcut: ViewModifier {
    let key: KeyEquivalent
    let modifiers: EventModifiers
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.keyboardShortcut(key, modifiers: modifiers)
        } else {
            content
        }
    }
}
