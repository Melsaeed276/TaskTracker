import SwiftUI
import AppDesign
import AppFeature
import TaskDomain

struct TimerTabView: View {
    let timer: ActiveTimerController
    let today: TodayController
    let pool: PoolController
    var onOpenRelatedTask: ((UUID) -> Void)? = nil

    @State private var selectedPresetMinutes = 25
    @State private var isConfirmingReset = false

    private let presets = [15, 25, 30, 45, 60]

    private var relatedTask: Task? {
        guard let id = timer.relatedTaskID else { return nil }
        return today.tasks.first(where: { $0.id == id })
            ?? pool.tasks.first(where: { $0.id == id })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.l) {
                displayPager
                relatedTaskButton
                durationPresets
                primaryControls
                resetControl
                sessionHint
            }
            .navigationTitle("Timer")
            .navigationSurface()
            .task {
                await timer.reload()
                await today.reload()
                await pool.reload()
            }
        }
    }

    private var displayPager: some View {
        TimerDisplayModePager {
            TimelineView(.periodic(from: TimerUI.timelineAnchor, by: 1)) { context in
                TimerCountdownRow(
                    remainingText: timer.remainingListLabel(at: context.date) ?? idleRemainingLabel,
                    durationText: timer.sessionDurationLabel ?? idleDurationLabel,
                    isActive: timer.isActive,
                    isPaused: timer.isPaused,
                    fontSize: 64,
                    onPauseResume: {
                        Swift.Task { await performPrimaryAction() }
                    }
                )
            }
        } stopwatchPage: {
            VStack(spacing: AppSpacing.m) {
                TimelineView(.periodic(from: TimerUI.timelineAnchor, by: 0.1)) { context in
                    StopwatchAnalogFace(
                        elapsedText: timer.elapsedStopwatchDigital(at: context.date),
                        endTimeText: timer.endTimeLabel(at: context.date),
                        secondsAngle: timer.stopwatchHandAngles(at: context.date).seconds,
                        minutesAngle: timer.stopwatchHandAngles(at: context.date).minutes,
                        maxDiameter: 280
                    )
                }

                stopwatchControls
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var idleRemainingLabel: String {
        String(format: "%d:00", selectedPresetMinutes)
    }

    private var idleDurationLabel: String {
        ActiveTimerController.durationLabel(for: TimeInterval(selectedPresetMinutes * 60))
    }

    private var stopwatchControls: some View {
        HStack(spacing: AppSpacing.l) {
            TimerControlButton(
                title: stopwatchPrimaryTitle,
                systemImage: stopwatchPrimarySymbol,
                tone: (!timer.isActive || timer.isPaused) ? .positive : .neutral,
                diameter: 76
            ) {
                Swift.Task { await performPrimaryAction() }
            }
            .accessibilityLabel(stopwatchPrimaryTitle)
            .accessibilityIdentifier("timer.stopwatchStartPause")

            TimerControlButton(
                title: "Stop",
                systemImage: AppSymbols.Timer.stop,
                tone: .caution,
                diameter: 76
            ) {
                Swift.Task { await timer.stop() }
            }
            .disabled(!timer.isActive)
            .accessibilityLabel("Stop timer")
            .accessibilityIdentifier("timer.stopwatchStop")
        }
    }

    private var stopwatchPrimaryTitle: String {
        if !timer.isActive { return "Start" }
        return timer.isPaused ? "Resume" : "Pause"
    }

    private var stopwatchPrimarySymbol: String {
        if !timer.isActive { return AppSymbols.Timer.resume }
        return timer.isPaused ? AppSymbols.Timer.resume : AppSymbols.Timer.pause
    }

    @ViewBuilder
    private var relatedTaskButton: some View {
        if timer.isActive, let task = relatedTask {
            Button {
                onOpenRelatedTask?(task.id)
            } label: {
                Label(task.title, systemImage: AppSymbols.Navigation.taskHub)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, AppSpacing.m)
            .accessibilityLabel("Open task \(task.title)")
            .accessibilityIdentifier("timer.openRelatedTask")
        } else if timer.isActive, timer.relatedTaskID != nil {
            Text("Linked task is not on Today or in the Pool.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.m)
        }
    }

    @ViewBuilder
    private var durationPresets: some View {
        if !timer.isActive {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                Text("Duration")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: AppSpacing.s) {
                    ForEach(presets, id: \.self) { minutes in
                        Button("\(minutes)m") {
                            selectedPresetMinutes = minutes
                        }
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, AppSpacing.m)
                        .padding(.vertical, AppSpacing.s)
                        .foregroundStyle(selectedPresetMinutes == minutes ? Color.green : .primary)
                        .floatingControlSurface()
                        .accessibilityLabel("\(minutes) minutes")
                        .accessibilityIdentifier("timer.preset.\(minutes)")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppSpacing.m)
        }
    }

    @ViewBuilder
    private var primaryControls: some View {
        if !timer.isActive {
            TimerControlButton(
                title: "Start",
                systemImage: AppSymbols.Timer.resume,
                tone: .positive,
                diameter: 98
            ) {
                Swift.Task { await performPrimaryAction() }
            }
            .accessibilityLabel("Start timer")
            .accessibilityIdentifier("timer.start")
        } else {
            TimerControlButton(
                title: "Stop",
                systemImage: AppSymbols.Timer.stop,
                tone: .caution,
                diameter: 92
            ) {
                Swift.Task { await timer.stop() }
            }
            .accessibilityLabel("Stop timer")
            .accessibilityIdentifier("timer.stop")
        }
    }

    private var resetControl: some View {
        Button("Reset", role: .destructive) {
            isConfirmingReset = true
        }
        .font(.callout)
        .disabled(!timer.isActive)
        .accessibilityLabel("Reset timer")
        .accessibilityIdentifier("timer.reset")
        .confirmationDialog(
            "Discard this session?",
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                Swift.Task { await timer.reset() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its elapsed time will not be kept in history. Stop keeps it instead.")
        }
    }

    @ViewBuilder
    private var sessionHint: some View {
        if timer.isActive {
            Text(
                timer.isPaused
                    ? "Paused — tap Resume to continue. Stop ends this session permanently."
                    : "Pause to take a break. Stop ends this session permanently."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, AppSpacing.m)
        }
    }

    private func performPrimaryAction() async {
        if !timer.isActive {
            await timer.start(duration: TimeInterval(selectedPresetMinutes * 60))
        } else if timer.isPaused {
            await timer.resume()
        } else {
            await timer.pause()
        }
    }
}
