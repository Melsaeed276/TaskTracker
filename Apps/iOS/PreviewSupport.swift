#if DEBUG
import Foundation
import SwiftUI
import AppDesign
import AppFeature
import TaskDomain
import TimerDomain
import AppData

/// In-memory doubles and sample data so every UI view can be previewed with
/// deterministic, varied mock state — no CloudKit, no live timer required.

// MARK: - Time source

struct PreviewTimeSource: TimerDomain.TimeSource, TaskDomain.TimeSource {
    let now: Date
    init(now: Date = Date(timeIntervalSince1970: 1_700_000_000)) { self.now = now }
}

private let previewBase = Date(timeIntervalSince1970: 1_700_000_000)

// MARK: - In-memory repositories

struct PreviewTimerEventRepository: TimerEventRepository {
    let events: [TimerEvent]
    func loadAllEvents() async throws -> [TimerEvent] { events }
    func append(_ event: TimerEvent) async throws {}
}

struct PreviewTaskRepository: TaskRepository {
    let tasks: [Task]
    func task(id: UUID) async throws -> Task? { tasks.first { $0.id == id } }
    func allTasks() async throws -> [Task] { tasks }
    func poolTasks() async throws -> [Task] { tasks.filter { $0.completedAt == nil } }
    func tasks(scheduledFor day: DayKey) async throws -> [Task] { tasks.filter { $0.scheduledDay == day } }
    func completedTasks() async throws -> [Task] { tasks.filter { $0.isCompleted } }
    func upsert(_ task: Task) async throws {}
    func deleteTask(id: UUID) async throws {}
}

struct PreviewTimeLogRepository: TaskTimeLogRepository {
    let adjustments: [TaskTimeAdjustment]
    let exclusions: [TaskSessionExclusion]
    func adjustments(forTaskID taskID: UUID) async throws -> [TaskTimeAdjustment] {
        adjustments.filter { $0.taskID == taskID }
    }
    func exclusions(forTaskID taskID: UUID) async throws -> [TaskSessionExclusion] {
        exclusions.filter { $0.taskID == taskID }
    }
    func upsertAdjustment(_ adjustment: TaskTimeAdjustment) async throws {}
    func deleteAdjustment(id: UUID) async throws {}
    func upsertExclusion(_ exclusion: TaskSessionExclusion) async throws {}
    func deleteExclusion(taskID: UUID, sessionID: UUID) async throws {}
}

// MARK: - Mock factory

@MainActor
enum PreviewMocks {
    static let base = previewBase
    static let deviceID = UUID()
    private static let sessionID = UUID()

    // MARK: Sample tasks

    static func makeTask(
        _ title: String,
        notes: String? = nil,
        completed: Bool = false,
        priority: TaskPriority = .none,
        id: UUID = UUID(),
        createdOffset: TimeInterval = 0,
        scheduled: DayKey? = DayKey.from(date: Date())
    ) -> Task {
        let now = Date()
        return Task(
            id: id,
            title: title,
            notes: notes,
            createdAt: now.addingTimeInterval(-createdOffset),
            completedAt: completed ? now : nil,
            scheduledDay: completed ? nil : scheduled,
            priority: priority,
            updatedAt: now
        )
    }

    static var sampleToday: [Task] {
        [
            makeTask("Write project plan", notes: "Cover goals and milestones", priority: .high, createdOffset: 400),
            makeTask("Review pull request", notes: nil, priority: .medium, createdOffset: 300),
            makeTask("Reply to emails", createdOffset: 200),
            makeTask("Book dentist appointment", completed: true, createdOffset: 100)
        ]
    }

    static var samplePool: [Task] {
        [
            makeTask("Idea: weekly review template", notes: "Sketch the structure", priority: .low, createdOffset: 500, scheduled: nil),
            makeTask("Renew domain", createdOffset: 400, scheduled: nil),
            makeTask("Read article on Swift concurrency", createdOffset: 300, scheduled: nil),
            makeTask("Archived reminder", completed: true, createdOffset: 600, scheduled: nil)
        ]
    }

    // MARK: Task controllers

    static func today(_ tasks: [Task] = sampleToday) -> TodayController {
        TodayController(repository: PreviewTaskRepository(tasks: tasks))
    }

    static func pool(
        _ tasks: [Task] = samplePool,
        showMode: PoolShowMode = .active,
        searchText: String = ""
    ) -> PoolController {
        let controller = PoolController(repository: PreviewTaskRepository(tasks: tasks))
        controller.showMode = showMode
        controller.searchText = searchText
        return controller
    }

    // MARK: Timer controllers

    static func idleTimer() -> ActiveTimerController {
        ActiveTimerController(
            repository: PreviewTimerEventRepository(events: []),
            timeSource: PreviewTimeSource(now: base)
        )
    }

    static func runningTimer(
        remaining: TimeInterval = 18 * 60,
        duration: TimeInterval = 25 * 60,
        relatedTaskID: UUID? = nil
    ) -> ActiveTimerController {
        let startedAt = base.addingTimeInterval(-(duration - remaining))
        let started = TimerEvent(
            id: UUID(),
            sessionID: sessionID,
            kind: TimerEventKind.started.rawValue,
            occurredAt: startedAt,
            deviceID: deviceID,
            lamport: 1,
            schemaVersion: 1,
            duration: duration,
            relatedTaskID: relatedTaskID
        )
        return ActiveTimerController(
            repository: PreviewTimerEventRepository(events: [started]),
            timeSource: PreviewTimeSource(now: base)
        )
    }

    static func pausedTimer(
        duration: TimeInterval = 25 * 60,
        accumulated: TimeInterval = 10 * 60,
        relatedTaskID: UUID? = nil
    ) -> ActiveTimerController {
        let startedAt = base.addingTimeInterval(-(accumulated + 300))
        let pausedAt = base.addingTimeInterval(-300)
        let started = TimerEvent(
            id: UUID(),
            sessionID: sessionID,
            kind: TimerEventKind.started.rawValue,
            occurredAt: startedAt,
            deviceID: deviceID,
            lamport: 1,
            schemaVersion: 1,
            duration: duration,
            relatedTaskID: relatedTaskID
        )
        let paused = TimerEvent(
            id: UUID(),
            sessionID: sessionID,
            kind: TimerEventKind.paused.rawValue,
            occurredAt: pausedAt,
            deviceID: deviceID,
            lamport: 2,
            schemaVersion: 1
        )
        return ActiveTimerController(
            repository: PreviewTimerEventRepository(events: [started, paused]),
            timeSource: PreviewTimeSource(now: base)
        )
    }

    // MARK: Time-log controller

    static func timeLog(
        for taskID: UUID,
        withAdjustment: Bool = true,
        excluded: Bool = false
    ) -> TaskTimeLogController {
        let started = TimerEvent(
            id: UUID(),
            sessionID: UUID(),
            kind: TimerEventKind.started.rawValue,
            occurredAt: base.addingTimeInterval(-2000),
            deviceID: deviceID,
            lamport: 1,
            schemaVersion: 1,
            duration: 25 * 60,
            relatedTaskID: taskID
        )
        let repo = PreviewTimerEventRepository(events: [started])

        var adjustments: [TaskTimeAdjustment] = []
        if withAdjustment {
            adjustments.append(
                TaskTimeAdjustment(
                    taskID: taskID,
                    durationSeconds: 30 * 60,
                    note: "Planning",
                    occurredAt: base.addingTimeInterval(-1000),
                    createdAt: base,
                    updatedAt: base
                )
            )
        }

        var exclusions: [TaskSessionExclusion] = []
        if excluded {
            exclusions.append(
                TaskSessionExclusion(taskID: taskID, sessionID: started.sessionID, createdAt: base)
            )
        }

        let logRepo = PreviewTimeLogRepository(adjustments: adjustments, exclusions: exclusions)
        return TaskTimeLogController(
            taskID: taskID,
            timerEvents: repo,
            timeLog: logRepo,
            timeSource: PreviewTimeSource(now: base)
        )
    }
}
#endif
