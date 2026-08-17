import SwiftUI
import AppDesign
import AppFeature
import TaskDomain

struct TimerTabView: View {
    enum DisplayMode: String, CaseIterable, Identifiable {
        case timer
        case stopwatch

        var id: String { rawValue }

        var title: String {
            switch self {
            case .timer: return "Timer"
            case .stopwatch: return "Stopwatch"
            }
        }

        var symbol: String {
            switch self {
            case .timer: return AppSymbols.Navigation.timer
            case .stopwatch: return "stopwatch"
            }
        }
    }

    let timer: ActiveTimerController
    let today: TodayController
    let pool: PoolController
    var onOpenRelatedTask: ((UUID) -> Void)? = nil

    @State private var selectedPresetMinutes = 25
    @State private var displayMode: DisplayMode
    @State private var selectedTaskID: UUID?
    @State private var isSelectingTask = false
    @State private var isConfirmingReset = false

    private let presets = [15, 25, 30, 45, 60]

    init(
        timer: ActiveTimerController,
        today: TodayController,
        pool: PoolController,
        onOpenRelatedTask: ((UUID) -> Void)? = nil,
        initialDisplayMode: DisplayMode = .timer
    ) {
        self.timer = timer
        self.today = today
        self.pool = pool
        self.onOpenRelatedTask = onOpenRelatedTask
        self._displayMode = State(initialValue: initialDisplayMode)
    }

    private var relatedTask: Task? {
        guard let id = timer.relatedTaskID else { return nil }
        return today.tasks.first(where: { $0.id == id })
            ?? pool.tasks.first(where: { $0.id == id })
    }

    private var selectedTask: Task? {
        guard let selectedTaskID else { return nil }
        return task(withID: selectedTaskID)
    }

    private var availableTodayTasks: [Task] {
        today.tasks.filter { !$0.isCompleted }
    }

    private var availablePoolTasks: [Task] {
        let todayIDs = Set(availableTodayTasks.map(\.id))
        return pool.tasks.filter { !$0.isCompleted && !todayIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.m) {
                pageHeader
                modeSelector
                displayCard
                sessionHint
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppSpacing.m)
            .padding(.top, AppSpacing.s)
            .padding(.bottom, AppSpacing.s)
            .navigationTitle("Timer")
            .navigationBarHidden(true)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomControls
            }
            .sheet(isPresented: $isSelectingTask) {
                taskPickerSheet
            }
            .task {
                await timer.reload()
                await today.reload()
                await pool.reload()
            }
        }
    }

    private var pageHeader: some View {
        Text("Timer")
            .font(.largeTitle.weight(.bold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private var modeSelector: some View {
        SurfaceGroup {
            HStack(spacing: AppSpacing.xs) {
                ForEach(DisplayMode.allCases) { mode in
                    modeButton(mode)
                }
            }
            .padding(AppSpacing.xs)
            .background(.regularMaterial, in: Capsule())
        }
        .accessibilityElement(children: .contain)
    }

    private func modeButton(_ mode: DisplayMode) -> some View {
        let isSelected = displayMode == mode
        return Button {
            withAnimation(.snappy(duration: AppDuration.normal)) {
                displayMode = mode
            }
        } label: {
            Label(mode.title, systemImage: mode.symbol)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, AppSpacing.s)
                .foregroundStyle(isSelected ? Color.primary : .secondary)
                .background {
                    if isSelected {
                        Capsule().fill(.regularMaterial)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("timer.mode.\(mode.rawValue)")
    }

    private var displayCard: some View {
        TimelineView(.periodic(from: TimerUI.timelineAnchor, by: timelineInterval)) { context in
            VStack(spacing: AppSpacing.l) {


                switch displayMode {
                case .timer:
                    timerFace(at: context.date)
                case .stopwatch:
                    stopwatchFace(at: context.date)
                }
            }
            .frame(maxWidth: .infinity, minHeight: displayMode == .stopwatch ? 300 : 236)
            .padding(.horizontal, AppSpacing.l)
            .padding(.vertical, AppSpacing.l)
            .background {
                RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                    .fill(.regularMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                    .strokeBorder(.secondary.opacity(0.16), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
            .onTapGesture {
                if timer.isActive {
                    Swift.Task { await performPrimaryAction() }
                } else {
                    isSelectingTask = true
                }
            }
        }
    }

    private var timelineInterval: TimeInterval {
        displayMode == .stopwatch && timer.isActive && !timer.isPaused ? 0.1 : 1
    }

    private var statusBadge: some View {
        Label(statusTitle, systemImage: statusSymbol)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.5)
            .foregroundStyle(statusTint)
            .padding(.horizontal, AppSpacing.m)
            .padding(.vertical, AppSpacing.s)
            .background(.regularMaterial, in: Capsule())
            .accessibilityIdentifier("timer.status")
    }

    private var focusTargetButton: some View {
        Button {
            if timer.isActive, let task = relatedTask {
                onOpenRelatedTask?(task.id)
            } else if !timer.isActive {
                isSelectingTask = true
            }
        } label: {
            HStack(spacing: AppSpacing.s) {
                Image(systemName: AppSymbols.Navigation.taskHub)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(focusTargetTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(focusTargetSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: AppSpacing.s)

                if !timer.isActive || relatedTask != nil {
                    Image(systemName: timer.isActive ? "chevron.right" : "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, AppSpacing.m)
            .padding(.vertical, AppSpacing.s)
            .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(timer.isActive && relatedTask == nil)
        .accessibilityLabel(focusTargetTitle)
        .accessibilityHint(timer.isActive ? "Open the linked task" : "Choose a task for this timer")
        .accessibilityIdentifier("timer.focusTarget")
    }

    private var focusTargetTitle: String {
        if timer.isActive {
            if timer.relatedTaskID != nil, relatedTask == nil {
                return "Linked task unavailable"
            }
            return relatedTask?.title ?? "Focus session"
        }
        return selectedTask?.title ?? "Choose a task"
    }

    private var focusTargetSubtitle: String {
        if timer.isActive {
            if timer.relatedTaskID != nil, relatedTask == nil {
                return "Not on Today or in the Pool"
            }
            return timer.isPaused ? "Paused with time left" : "Timer is linked and running"
        }
        return selectedTask == nil ? "Optional - start without a task if needed" : "Timer will start linked to this task"
    }

    private var setupDock: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            taskSelectionSection

            durationPresets
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var taskSelectionSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Text("Task")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)

            focusTargetButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusTitle: String {
        if !timer.isActive { return "Ready" }
        return timer.isPaused ? "Paused" : "Running"
    }

    private var statusSymbol: String {
        if !timer.isActive { return AppSymbols.Timer.idle }
        return timer.isPaused ? AppSymbols.Timer.pause : AppSymbols.Timer.resume
    }

    private var statusTint: Color {
        if !timer.isActive { return .secondary }
        return timer.isPaused ? TimerDisplayTokens.timerPauseRingColor : .green
    }

    @ViewBuilder
    private func timerFace(at date: Date) -> some View {
        VStack(spacing: AppSpacing.s) {
            Text(timer.remainingListLabel(at: date) ?? idleRemainingLabel)
                .font(.system(size: 64, weight: .thin, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.48)
                .contentTransition(.numericText())
                .accessibilityIdentifier("timer.display")

            Text(timer.sessionDurationLabel ?? idleDurationLabel)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(timer.isActive ? "Focus session" : "Ready when you are")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Timer, \(timer.remainingListLabel(at: date) ?? idleRemainingLabel) remaining")
    }

    @ViewBuilder
    private func stopwatchFace(at date: Date) -> some View {
        VStack(spacing: AppSpacing.s) {
            ZStack {
//                RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
//                    .fill(.thinMaterial)

                VStack(spacing: AppSpacing.s) {
                    Text(timer.elapsedStopwatchDigital(at: date))
                        .font(.system(size: 64, weight: .thin, design: .rounded).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("timer.stopwatchDigital")

                    Text(timer.isActive ? "Tap to pause" : "Tap to start")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(AppSpacing.l)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: 250)
//            .overlay {
//                RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
//                    .strokeBorder(.secondary.opacity(0.14), lineWidth: 1)
//            }

            Text(timer.isActive ? "Elapsed time" : "Start to track elapsed time")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stopwatch, elapsed \(timer.elapsedStopwatchDigital(at: date))")
    }

    private var idleRemainingLabel: String {
        String(format: "%d:00", selectedPresetMinutes)
    }

    private var idleDurationLabel: String {
        ActiveTimerController.durationLabel(for: TimeInterval(selectedPresetMinutes * 60))
    }

    private var stopwatchPrimaryTitle: String {
        if !timer.isActive { return "Start" }
        return timer.isPaused ? "Resume" : "Pause"
    }

    private var stopwatchPrimarySymbol: String {
        if !timer.isActive { return AppSymbols.Timer.resume }
        return timer.isPaused ? AppSymbols.Timer.resume : AppSymbols.Timer.pause
    }

    private var taskPickerSheet: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        startFromPicker(taskID: nil)
                    } label: {
                        taskPickerRow(
                            title: "No task",
                            subtitle: "Start a standalone \(idleDurationLabel) timer",
                            isSelected: selectedTaskID == nil
                        )
                    }
                }

                if !availableTodayTasks.isEmpty {
                    Section("Today") {
                        ForEach(availableTodayTasks) { task in
                            Button {
                                startFromPicker(taskID: task.id)
                            } label: {
                                taskPickerRow(
                                    title: task.title,
                                    subtitle: taskPickerSubtitle(scope: "Today", task: task),
                                    isSelected: selectedTaskID == task.id
                                )
                            }
                        }
                    }
                }

                if !availablePoolTasks.isEmpty {
                    Section("Pool") {
                        ForEach(availablePoolTasks) { task in
                            Button {
                                startFromPicker(taskID: task.id)
                            } label: {
                                taskPickerRow(
                                    title: task.title,
                                    subtitle: taskPickerSubtitle(scope: "Pool", task: task),
                                    isSelected: selectedTaskID == task.id
                                )
                            }
                        }
                    }
                }
            }
            .navigationTitle("Start Timer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isSelectingTask = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func taskPickerSubtitle(scope: String, task: Task) -> String {
        let timerText = "Start \(idleDurationLabel)"
        if task.priority == .none {
            return "\(scope) · \(timerText)"
        }
        return "\(scope) · \(task.priority.displayName) priority · \(timerText)"
    }

    private func taskPickerRow(title: String, subtitle: String, isSelected: Bool) -> some View {
        HStack(spacing: AppSpacing.m) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var durationPresets: some View {
        if !timer.isActive {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                Text("Duration")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Fall back to a horizontal scroll when the row would overflow the
                // narrowest iPhone instead of letting presets clip off-screen.
                ViewThatFits(in: .horizontal) {
                    presetsRow
                    ScrollView(.horizontal, showsIndicators: false) {
                        presetsRow
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var presetsRow: some View {
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

    private var resetControl: some View {
        Button(role: .destructive) {
            isConfirmingReset = true
        } label: {
            Label("Reset", systemImage: "arrow.counterclockwise")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red)
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

    private var bottomControls: some View {
        SurfaceGroup {
            VStack(spacing: AppSpacing.s) {
                if displayMode == .timer {
                    if !timer.isActive {
                        setupDock
                    } else if timer.relatedTaskID != nil {
                        focusTargetButton
                    }
                }

                HStack(spacing: AppSpacing.m) {
                    primaryActionButton(
                        title: stopwatchPrimaryTitle,
                        systemImage: stopwatchPrimarySymbol,
                        foreground: (!timer.isActive || timer.isPaused) ? .green : .primary,
                        accessibilityIdentifier: "timer.primaryAction"
                    ) {
                        Swift.Task { await performPrimaryAction() }
                    }

                    if timer.isActive {
                        compactActionButton(
                            title: "Stop",
                            systemImage: AppSymbols.Timer.stop,
                            foreground: .red,
                            accessibilityIdentifier: "timer.stop"
                        ) {
                            Swift.Task { await timer.stop() }
                        }

                        compactResetControl
                    }
                }
            }
            .padding(.horizontal, AppSpacing.m)
            .padding(.top, AppSpacing.s)
            .padding(.bottom, AppSpacing.m)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) {
                Divider()
            }
        }
    }

    private func primaryActionButton(
        title: String,
        systemImage: String,
        foreground: Color,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Capsule())
        }
        .buttonStyle(TimerActionButtonStyle(shape: Capsule()))
        .foregroundStyle(foreground)
        .background(foreground.opacity(0.12), in: Capsule())
        .animation(.snappy(duration: AppDuration.fast), value: timer.isActive)
        .animation(.snappy(duration: AppDuration.fast), value: timer.isPaused)
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func compactActionButton(
        title: String,
        systemImage: String,
        foreground: Color,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(width: 52, height: 52)
                .contentShape(Circle())
        }
        .buttonStyle(TimerActionButtonStyle(shape: Circle()))
        .foregroundStyle(foreground)
        .background(foreground.opacity(0.12), in: Circle())
        .animation(.snappy(duration: AppDuration.fast), value: timer.isActive)
        .animation(.snappy(duration: AppDuration.fast), value: timer.isPaused)
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var compactResetControl: some View {
        Button(role: .destructive) {
            isConfirmingReset = true
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.subheadline.weight(.semibold))
                .frame(width: 52, height: 52)
                .contentShape(Circle())
        }
        .buttonStyle(TimerActionButtonStyle(shape: Circle()))
        .foregroundStyle(.red)
        .background(.red.opacity(0.12), in: Circle())
        .disabled(!timer.isActive)
        .animation(.snappy(duration: AppDuration.fast), value: timer.isActive)
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
                    ? "Paused - tap Resume to continue. Stop ends this session permanently."
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
            await timer.start(
                duration: TimeInterval(selectedPresetMinutes * 60),
                relatedTaskID: selectedTaskID
            )
        } else if timer.isPaused {
            await timer.resume()
        } else {
            await timer.pause()
        }
    }

    private func startFromPicker(taskID: UUID?) {
        selectedTaskID = taskID
        isSelectingTask = false
        Swift.Task {
            await timer.start(
                duration: TimeInterval(selectedPresetMinutes * 60),
                relatedTaskID: taskID
            )
        }
    }

    private func task(withID id: UUID) -> Task? {
        today.tasks.first(where: { $0.id == id })
            ?? pool.tasks.first(where: { $0.id == id })
    }
}

private struct TimerActionButtonStyle<S: Shape>: ButtonStyle {
    let shape: S

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .contentShape(shape)
            .animation(.snappy(duration: AppDuration.fast), value: configuration.isPressed)
    }
}

#if DEBUG
#Preview("Timer - Idle") {
    let timer = PreviewMocks.idleTimer()
    TimerTabView(timer: timer, today: PreviewMocks.today(), pool: PreviewMocks.pool())
        .task { await timer.reload() }
}

#Preview("Timer - Compact Idle") {
    let timer = PreviewMocks.idleTimer()
    TimerTabView(timer: timer, today: PreviewMocks.today(), pool: PreviewMocks.pool())
        .frame(width: 375, height: 667)
        .task { await timer.reload() }
}

#Preview("Timer - Running") {
    let timer = PreviewMocks.runningTimer()
    TimerTabView(timer: timer, today: PreviewMocks.today(), pool: PreviewMocks.pool())
        .task { await timer.reload() }
}

#Preview("Timer - Compact Running") {
    let timer = PreviewMocks.runningTimer()
    TimerTabView(timer: timer, today: PreviewMocks.today(), pool: PreviewMocks.pool())
        .frame(width: 375, height: 667)
        .task { await timer.reload() }
}

#Preview("Timer - Paused") {
    let timer = PreviewMocks.pausedTimer()
    TimerTabView(timer: timer, today: PreviewMocks.today(), pool: PreviewMocks.pool())
        .task { await timer.reload() }
}

#Preview("Timer - Linked Task") {
    let task = PreviewMocks.makeTask("Write project plan", priority: .high)
    let timer = PreviewMocks.runningTimer(relatedTaskID: task.id)
    TimerTabView(timer: timer, today: PreviewMocks.today([task]), pool: PreviewMocks.pool())
        .task { await timer.reload() }
}

#Preview("Stopwatch - Running") {
    let timer = PreviewMocks.runningTimer()
    TimerTabView(
        timer: timer,
        today: PreviewMocks.today(),
        pool: PreviewMocks.pool(),
        initialDisplayMode: .stopwatch
    )
    .task { await timer.reload() }
}
#endif
