import SwiftUI
import AppDesign
import AppFeature
import TaskDomain

/// Shared edit payload for title, notes, schedule, and priority.
struct TaskEditDraft: Equatable {
    var title: String
    var notes: String
    /// `nil` means Pool (unscheduled).
    var scheduledDay: DayKey?
    var priority: TaskPriority
    var timerPresetMinutes: Int
}

struct TaskEditSheet: View {
    let task: Task
    var timer: ActiveTimerController?
    /// Builds a per-task time log controller (sessions stay immutable; adjustments are editable).
    var makeTimeLog: ((UUID) -> TaskTimeLogController)?
    let onSave: (TaskEditDraft) async -> Void
    var onDelete: (() async -> Void)?
    /// Called after a focus session is started from this sheet (sheet is dismissed first).
    var onStartedTimer: (() -> Void)? = nil
    /// Opens the Timer tab while keeping or dismissing this sheet as the caller prefers.
    var onOpenTimerTab: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var draft: TaskEditDraft
    @State private var isScheduled: Bool
    @State private var scheduledDate: Date
    @State private var isConfirmingDelete = false
    @State private var timeLog: TaskTimeLogController?
    @State private var isAddingTime = false
    @State private var addMinutes = 25
    @State private var addNote = ""
    @State private var editingAdjustmentID: UUID?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case title
        case notes
    }

    private static let timerPresets = [15, 25, 30, 45, 60]

    init(
        task: Task,
        timer: ActiveTimerController? = nil,
        makeTimeLog: ((UUID) -> TaskTimeLogController)? = nil,
        onSave: @escaping (TaskEditDraft) async -> Void,
        onDelete: (() async -> Void)? = nil,
        onStartedTimer: (() -> Void)? = nil,
        onOpenTimerTab: (() -> Void)? = nil
    ) {
        self.task = task
        self.timer = timer
        self.makeTimeLog = makeTimeLog
        self.onSave = onSave
        self.onDelete = onDelete
        self.onStartedTimer = onStartedTimer
        self.onOpenTimerTab = onOpenTimerTab
        let initialDay = task.scheduledDay
        _draft = State(
            initialValue: TaskEditDraft(
                title: task.title,
                notes: task.notes ?? "",
                scheduledDay: initialDay,
                priority: task.priority,
                timerPresetMinutes: 25
            )
        )
        _isScheduled = State(initialValue: initialDay != nil)
        _scheduledDate = State(initialValue: initialDay?.date() ?? Date())
    }

    private var isLinkedActiveTimer: Bool {
        timer?.isLinked(toTaskID: task.id) == true
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if let timer, isLinkedActiveTimer {
                    Section {
                        TimelineView(.periodic(from: TimerUI.timelineAnchor, by: 1)) { context in
                            TaskTimerActionBar(
                                countdown: timer.compactLabel(at: context.date) ?? "0:00",
                                statusText: timer.isPaused ? "Paused" : "Running",
                                isPaused: timer.isPaused,
                                onPauseResume: {
                                    Swift.Task { @MainActor in
                                        if timer.isPaused {
                                            await timer.resume()
                                        } else {
                                            await timer.pause()
                                        }
                                    }
                                },
                                onStop: {
                                    Swift.Task { @MainActor in
                                        await timer.stop()
                                        await timeLog?.reload()
                                    }
                                },
                                onOpenTimer: {
                                    dismiss()
                                    onOpenTimerTab?()
                                }
                            )
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }

                Section {
                    TextField("Title", text: $draft.title)
                        .focused($focusedField, equals: .title)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .notes }
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($focusedField, equals: .notes)
                        .submitLabel(.done)
                }

                Section("Date") {
                    Toggle("Scheduled", isOn: $isScheduled)
                        .accessibilityIdentifier("taskEdit.scheduledToggle")
                    if isScheduled {
                        DatePicker(
                            "Day",
                            selection: $scheduledDate,
                            displayedComponents: .date
                        )
                        .accessibilityIdentifier("taskEdit.datePicker")
                    } else {
                        Text("Unscheduled tasks live in the Pool.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Priority") {
                    Picker("Priority", selection: $draft.priority) {
                        ForEach(TaskPriority.allCases, id: \.self) { priority in
                            Text(priority.displayName).tag(priority)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("taskEdit.priorityPicker")
                }

                if let timer, !isLinkedActiveTimer {
                    Section("Timer") {
                        Picker("Duration", selection: $draft.timerPresetMinutes) {
                            ForEach(Self.timerPresets, id: \.self) { minutes in
                                Text("\(minutes) min").tag(minutes)
                            }
                        }
                        .accessibilityIdentifier("taskEdit.timerPresetPicker")

                        Button {
                            Swift.Task { @MainActor in
                                await timer.start(
                                    duration: TimeInterval(draft.timerPresetMinutes * 60),
                                    relatedTaskID: task.id
                                )
                                dismiss()
                                onStartedTimer?()
                            }
                        } label: {
                            Label(
                                timer.isActive ? "Replace Timer for Task" : "Start Timer for Task",
                                systemImage: AppSymbols.Timer.resume
                            )
                        }
                        .accessibilityIdentifier("taskEdit.startTimerButton")

                        if timer.isActive {
                            Text(
                                timer.isPaused
                                    ? "A focus session is paused. Resume it from the Timer tab to continue, or replace it here. Stop ends it permanently."
                                    : "A focus session is running. Use Pause/Resume on the Timer tab to continue later. Starting here replaces it."
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                if let timeLog {
                    timeSpentSection(timeLog)
                }

                if onDelete != nil {
                    Section {
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete Task", systemImage: AppSymbols.Tasks.delete)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("taskEdit.deleteButton")
                    }
                }
            }
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .navigationSurface()
            .safeAreaInset(edge: .bottom, spacing: AppSpacing.s) {
                VStack(spacing: AppSpacing.s) {
                    Button(action: save) {
                        Text("Save")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canSave)
                    .accessibilityIdentifier("taskEdit.saveButton")
                }
                .padding(.horizontal, AppSpacing.m)
                .padding(.top, AppSpacing.s)
                .padding(.bottom, AppSpacing.s)
                .background(.bar)
            }
            .confirmationDialog(
                "Delete this task?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Task", role: .destructive) {
                    Swift.Task {
                        await onDelete?()
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the task permanently. Timer history for it is kept in the event log.")
            }
            .sheet(isPresented: $isAddingTime) {
                addTimeSheet
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .task {
                if timeLog == nil {
                    timeLog = makeTimeLog?(task.id)
                }
                await timeLog?.reload()
                if !isLinkedActiveTimer {
                    focusedField = .title
                }
            }
            .onChange(of: isScheduled) { _, scheduled in
                if scheduled, draft.scheduledDay == nil {
                    draft.scheduledDay = DayKey.from(date: scheduledDate)
                } else if !scheduled {
                    draft.scheduledDay = nil
                }
            }
            .onChange(of: scheduledDate) { _, date in
                guard isScheduled else { return }
                draft.scheduledDay = DayKey.from(date: date)
            }
        }
    }

    @ViewBuilder
    private func timeSpentSection(_ timeLog: TaskTimeLogController) -> some View {
        Section {
            HStack {
                Text("Total")
                Spacer()
                Text(TaskTimeLogController.formatDuration(timeLog.totalSpent))
                    .font(.body.monospacedDigit().weight(.semibold))
                    .accessibilityIdentifier("taskEdit.timeTotal")
            }

            ForEach(timeLog.entries) { entry in
                timeLogRow(entry, timeLog: timeLog)
            }

            Button {
                addMinutes = 25
                addNote = ""
                editingAdjustmentID = nil
                isAddingTime = true
            } label: {
                Label("Add Time", systemImage: AppSymbols.Tasks.add)
            }
            .accessibilityIdentifier("taskEdit.addTimeButton")
        } header: {
            Text("Time Spent")
        } footer: {
            Text("Focus sessions are immutable. Add, edit, or remove manual adjustments; hide a session from this total without deleting the timer log.")
        }
    }

    @ViewBuilder
    private func timeLogRow(_ entry: TaskTimeLogEntry, timeLog: TaskTimeLogController) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                switch entry.kind {
                case .session(_, let status):
                    Text(status)
                        .font(.subheadline.weight(.semibold))
                        .strikethrough(entry.isExcluded)
                case .adjustment:
                    Text(entry.note?.isEmpty == false ? entry.note! : "Manual time")
                        .font(.subheadline.weight(.semibold))
                }
                Text(entry.occurredAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(TaskTimeLogController.formatDuration(entry.duration))
                .font(.body.monospacedDigit())
                .foregroundStyle(entry.isExcluded ? .secondary : .primary)
                .strikethrough(entry.isExcluded)
        }
        .opacity(entry.isExcluded ? 0.55 : 1)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            switch entry.kind {
            case .session(let sessionID, _):
                if entry.isExcluded {
                    Button("Restore") {
                        Swift.Task { await timeLog.includeSession(sessionID: sessionID) }
                    }
                    .tint(.accentColor)
                } else {
                    Button("Hide", role: .destructive) {
                        Swift.Task { await timeLog.excludeSession(sessionID: sessionID) }
                    }
                }
            case .adjustment:
                Button("Edit") {
                    editingAdjustmentID = entry.id
                    addMinutes = max(1, Int((entry.duration / 60).rounded()))
                    addNote = entry.note ?? ""
                    isAddingTime = true
                }
                .tint(.accentColor)
                Button("Delete", role: .destructive) {
                    Swift.Task { await timeLog.deleteAdjustment(id: entry.id) }
                }
            }
        }
    }

    private var addTimeSheet: some View {
        NavigationStack {
            Form {
                Stepper(value: $addMinutes, in: 1...12 * 60) {
                    Text("\(addMinutes) min")
                }
                TextField("Note (optional)", text: $addNote)
            }
            .navigationTitle(editingAdjustmentID == nil ? "Add Time" : "Edit Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isAddingTime = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Swift.Task { @MainActor in
                            let seconds = TimeInterval(addMinutes * 60)
                            let note = addNote
                            if let id = editingAdjustmentID {
                                await timeLog?.editAdjustment(id: id, durationSeconds: seconds, note: note)
                            } else {
                                await timeLog?.addAdjustment(durationSeconds: seconds, note: note)
                            }
                            isAddingTime = false
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard canSave else { return }
        var payload = draft
        payload.scheduledDay = isScheduled ? DayKey.from(date: scheduledDate) : nil
        let trimmedNotes = payload.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        payload.notes = trimmedNotes
        Swift.Task {
            await onSave(payload)
            dismiss()
        }
    }
}
