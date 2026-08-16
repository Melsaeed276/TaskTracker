import Foundation
import CoreData
import Testing
import TaskDomain
import TimerDomain
@testable import AppData

@Suite("AppData")
struct AppDataTests {
    @Test("In-memory container round-trip: TaskRecord ↔ Task")
    func taskRoundTrip() async throws {
        let container = try await MainActor.run { try AppDataModelContainer.makeLocalInMemory() }
        let repo = SwiftDataTaskRepository(modelContainer: container)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let task = Task(
            id: UUID(),
            title: "Hello",
            notes: "Notes",
            createdAt: now,
            completedAt: nil,
            scheduledDay: DayKey(rawValue: "2026-08-09"),
            updatedAt: now
        )

        try await repo.upsert(task)
        let loaded = try await repo.task(id: task.id)
        #expect(loaded == task)
    }

    @Test("In-memory container round-trip: TimerEventRecord ↔ TimerEvent")
    func timerEventRoundTrip() async throws {
        let container = try await MainActor.run { try AppDataModelContainer.makeLocalInMemory() }
        let repo = SwiftDataTimerEventRepository(modelContainer: container)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let event = TimerEvent(
            id: UUID(),
            sessionID: UUID(),
            kind: TimerEventKind.started.rawValue,
            occurredAt: now,
            deviceID: UUID(),
            lamport: 1,
            schemaVersion: 1,
            duration: 25 * 60,
            relatedTaskID: UUID()
        )

        try await repo.append(event)
        let all = try await repo.loadAllEvents()
        #expect(all.contains(event))
    }

    @Test("On-disk pool query returns every unscheduled, incomplete task")
    func onDiskPoolQueryReturnsAllTasks() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskTracker-AppDataTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let storeURL = rootURL.appendingPathComponent("TaskTracker.sqlite")

        let initialContainer = try await MainActor.run {
            try AppDataModelContainer.makeLocalOnDisk(storeURL: storeURL)
        }
        let initialRepo = SwiftDataTaskRepository(modelContainer: initialContainer)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let poolTasks = (1...5).map { index in
            Task(
                id: UUID(),
                title: "Pool \(index)",
                notes: index.isMultiple(of: 2) ? "Note \(index)" : nil,
                createdAt: now.addingTimeInterval(TimeInterval(index)),
                completedAt: nil,
                scheduledDay: nil,
                updatedAt: now.addingTimeInterval(TimeInterval(index))
            )
        }

        for task in poolTasks {
            try await initialRepo.upsert(task)
        }

        // Control records should be excluded by `poolTasks()`.
        let scheduled = Task(
            id: UUID(),
            title: "Scheduled",
            notes: nil,
            createdAt: now,
            completedAt: nil,
            scheduledDay: DayKey(rawValue: "2026-08-15"),
            updatedAt: now
        )
        let completed = Task(
            id: UUID(),
            title: "Completed",
            notes: nil,
            createdAt: now,
            completedAt: now,
            scheduledDay: nil,
            updatedAt: now
        )
        try await initialRepo.upsert(scheduled)
        try await initialRepo.upsert(completed)

        // Re-open the sqlite store to prove the on-disk path, not just one in-memory context view.
        let reopenedContainer = try await MainActor.run {
            try AppDataModelContainer.makeLocalOnDisk(storeURL: storeURL)
        }
        let reopenedRepo = SwiftDataTaskRepository(modelContainer: reopenedContainer)
        let loaded = try await reopenedRepo.poolTasks()

        #expect(loaded.count == poolTasks.count)
        #expect(Set(loaded.map(\.id)) == Set(poolTasks.map(\.id)))
    }

    @Test("On-disk Today reload composition returns scheduled + completed-for-today after reopen")
    func onDiskTodayReloadCompositionReturnsExpectedTasks() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskTracker-AppDataTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let storeURL = rootURL.appendingPathComponent("TaskTracker.sqlite")
        let initialContainer = try await MainActor.run {
            try AppDataModelContainer.makeLocalOnDisk(storeURL: storeURL)
        }
        let initialRepo = SwiftDataTaskRepository(modelContainer: initialContainer)

        let now = Date(timeIntervalSince1970: 1_700_010_000)
        let today = DayKey(rawValue: "2026-08-15")
        let yesterday = DayKey(rawValue: "2026-08-14")

        let openToday = Task(
            id: UUID(),
            title: "Open today",
            notes: nil,
            createdAt: now,
            completedAt: nil,
            scheduledDay: today,
            updatedAt: now
        )
        let completedToday = Task(
            id: UUID(),
            title: "Completed today",
            notes: nil,
            createdAt: now.addingTimeInterval(1),
            completedAt: now.addingTimeInterval(60),
            scheduledDay: today,
            updatedAt: now.addingTimeInterval(60)
        )
        let completedYesterday = Task(
            id: UUID(),
            title: "Completed yesterday schedule",
            notes: nil,
            createdAt: now.addingTimeInterval(2),
            completedAt: now.addingTimeInterval(60),
            scheduledDay: yesterday,
            updatedAt: now.addingTimeInterval(60)
        )
        let poolTask = Task(
            id: UUID(),
            title: "Pool task",
            notes: nil,
            createdAt: now.addingTimeInterval(3),
            completedAt: nil,
            scheduledDay: nil,
            updatedAt: now.addingTimeInterval(3)
        )

        for task in [openToday, completedToday, completedYesterday, poolTask] {
            try await initialRepo.upsert(task)
        }

        let reopenedContainer = try await MainActor.run {
            try AppDataModelContainer.makeLocalOnDisk(storeURL: storeURL)
        }
        let reopenedRepo = SwiftDataTaskRepository(modelContainer: reopenedContainer)

        let open = try await reopenedRepo.tasks(scheduledFor: today)
        let completedForToday = try await reopenedRepo.completedTasks().filter { $0.scheduledDay == today }
        let combined = (open + completedForToday).sorted(by: { $0.createdAt < $1.createdAt })

        #expect(combined.count == 2)
        #expect(Set(combined.map(\.id)) == Set([openToday.id, completedToday.id]))
    }

    @Test("On-disk timer events survive reopen and evaluate identically")
    func onDiskTimerEventRoundTripAndEvaluationParity() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskTracker-AppDataTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let storeURL = rootURL.appendingPathComponent("TaskTracker.sqlite")
        let initialContainer = try await MainActor.run {
            try AppDataModelContainer.makeLocalOnDisk(storeURL: storeURL)
        }
        let initialRepo = SwiftDataTimerEventRepository(modelContainer: initialContainer)

        let sessionID = UUID()
        let deviceID = UUID()
        let base = Date(timeIntervalSince1970: 1_700_020_000)
        let events: [TimerEvent] = [
            TimerEvent(
                id: UUID(),
                sessionID: sessionID,
                kind: TimerEventKind.started.rawValue,
                occurredAt: base,
                deviceID: deviceID,
                lamport: 1,
                schemaVersion: 1,
                duration: 25 * 60
            ),
            TimerEvent(
                id: UUID(),
                sessionID: sessionID,
                kind: TimerEventKind.paused.rawValue,
                occurredAt: base.addingTimeInterval(20),
                deviceID: deviceID,
                lamport: 2,
                schemaVersion: 1
            ),
            TimerEvent(
                id: UUID(),
                sessionID: sessionID,
                kind: TimerEventKind.resumed.rawValue,
                occurredAt: base.addingTimeInterval(40),
                deviceID: deviceID,
                lamport: 3,
                schemaVersion: 1
            ),
            TimerEvent(
                id: UUID(),
                sessionID: sessionID,
                kind: TimerEventKind.stopped.rawValue,
                occurredAt: base.addingTimeInterval(60),
                deviceID: deviceID,
                lamport: 4,
                schemaVersion: 1
            )
        ]

        for event in events {
            try await initialRepo.append(event)
        }

        let reopenedContainer = try await MainActor.run {
            try AppDataModelContainer.makeLocalOnDisk(storeURL: storeURL)
        }
        let reopenedRepo = SwiftDataTimerEventRepository(modelContainer: reopenedContainer)
        let loaded = try await reopenedRepo.loadAllEvents()

        #expect(Set(loaded.map(\.id)) == Set(events.map(\.id)))

        let at = base.addingTimeInterval(120)
        let expected = TimerEngine.evaluateActiveTimer(events: events, at: at)
        let actual = TimerEngine.evaluateActiveTimer(events: loaded, at: at)
        #expect(actual == expected)
    }

    @Test("Remote-change notification predicate only allows completed imports")
    func remoteChangeNotificationPredicate() {
        let endDate = Date(timeIntervalSince1970: 1_700_030_000)

        #expect(AppDataModelContainer.shouldPostRemoteChangeNotification(
            eventType: .import,
            succeeded: true,
            endDate: endDate
        ))
        #expect(!AppDataModelContainer.shouldPostRemoteChangeNotification(
            eventType: .import,
            succeeded: false,
            endDate: endDate
        ))
        #expect(!AppDataModelContainer.shouldPostRemoteChangeNotification(
            eventType: .import,
            succeeded: true,
            endDate: nil
        ))
        #expect(!AppDataModelContainer.shouldPostRemoteChangeNotification(
            eventType: .setup,
            succeeded: true,
            endDate: endDate
        ))
        #expect(!AppDataModelContainer.shouldPostRemoteChangeNotification(
            eventType: .export,
            succeeded: true,
            endDate: endDate
        ))
    }
}
