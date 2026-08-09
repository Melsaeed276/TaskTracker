import Foundation
import Testing
import TaskDomain
import TimerDomain
@testable import AppData

@Suite("AppData")
struct AppDataTests {
    @Test("In-memory container round-trip: TaskRecord ↔ Task")
    func taskRoundTrip() throws {
        let container = try AppDataModelContainer.makeLocalInMemory()
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

        try repo.upsert(task)
        let loaded = try repo.task(id: task.id)
        #expect(loaded == task)
    }

    @Test("In-memory container round-trip: TimerEventRecord ↔ TimerEvent")
    func timerEventRoundTrip() throws {
        let container = try AppDataModelContainer.makeLocalInMemory()
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

        try repo.append(event)
        let all = try repo.loadAllEvents()
        #expect(all.contains(event))
    }
}
