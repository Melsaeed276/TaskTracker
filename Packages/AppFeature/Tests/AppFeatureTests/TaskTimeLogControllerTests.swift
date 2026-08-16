import Foundation
import Testing
import AppData
import TimerDomain
@testable import AppFeature

private final class AdjustableTimeSource: TimeSource, @unchecked Sendable {
    var now: Date
    init(now: Date) { self.now = now }
}

@Suite("TaskTimeLogController")
struct TaskTimeLogControllerTests {
    private let deviceA = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let deviceB = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    private let base = Date(timeIntervalSince1970: 2_000_000_000)

    @MainActor
    private func makeHarness(taskID: UUID) throws -> (
        TaskTimeLogController,
        SwiftDataTimerEventRepository,
        SwiftDataTaskTimeLogRepository,
        AdjustableTimeSource
    ) {
        let container = try AppDataModelContainer.makeLocalInMemory()
        let events = SwiftDataTimerEventRepository(modelContainer: container)
        let log = SwiftDataTaskTimeLogRepository(modelContainer: container)
        let clock = AdjustableTimeSource(now: base)
        let controller = TaskTimeLogController(
            taskID: taskID,
            timerEvents: events,
            timeLog: log,
            timeSource: clock
        )
        return (controller, events, log, clock)
    }

    @Test("two sequential task sessions contribute elapsed with supersession cutoff")
    @MainActor
    func sequentialSessionsTotalWithCutoff() async throws {
        let taskID = UUID()
        let (controller, events, _, clock) = try makeHarness(taskID: taskID)
        let sessionA = UUID()
        let sessionB = UUID()

        try await events.append(
            TimerEvent(
                id: UUID(),
                sessionID: sessionA,
                kind: TimerEventKind.started.rawValue,
                occurredAt: base,
                deviceID: deviceA,
                lamport: 1,
                schemaVersion: 1,
                duration: 600,
                relatedTaskID: taskID
            )
        )
        try await events.append(
            TimerEvent(
                id: UUID(),
                sessionID: sessionB,
                kind: TimerEventKind.started.rawValue,
                occurredAt: base.addingTimeInterval(120),
                deviceID: deviceB,
                lamport: 1,
                schemaVersion: 1,
                duration: 300,
                relatedTaskID: taskID
            )
        )
        try await events.append(
            TimerEvent(
                id: UUID(),
                sessionID: sessionB,
                kind: TimerEventKind.stopped.rawValue,
                occurredAt: base.addingTimeInterval(180),
                deviceID: deviceB,
                lamport: 2,
                schemaVersion: 1
            )
        )

        clock.now = base.addingTimeInterval(200)
        await controller.reload()

        // A ran 120s then superseded; B ran 60s then stopped.
        #expect(controller.totalSpent == 180)
        #expect(controller.entries.count == 2)
    }

    @Test("adjustment adds to total; delete adjustment restores prior total")
    @MainActor
    func adjustmentAddAndDelete() async throws {
        let taskID = UUID()
        let (controller, _, _, _) = try makeHarness(taskID: taskID)

        await controller.addAdjustment(durationSeconds: 90, note: "Manual")
        #expect(controller.totalSpent == 90)
        #expect(controller.entries.count == 1)

        let id = try #require(controller.entries.first?.id)
        await controller.deleteAdjustment(id: id)
        #expect(controller.totalSpent == 0)
        #expect(controller.entries.isEmpty)
    }

    @Test("excluding a session removes it from the total without deleting events")
    @MainActor
    func exclusionRemovesFromTotal() async throws {
        let taskID = UUID()
        let (controller, events, _, clock) = try makeHarness(taskID: taskID)
        let sessionID = UUID()

        try await events.append(
            TimerEvent(
                id: UUID(),
                sessionID: sessionID,
                kind: TimerEventKind.started.rawValue,
                occurredAt: base,
                deviceID: deviceA,
                lamport: 1,
                schemaVersion: 1,
                duration: 120,
                relatedTaskID: taskID
            )
        )
        try await events.append(
            TimerEvent(
                id: UUID(),
                sessionID: sessionID,
                kind: TimerEventKind.stopped.rawValue,
                occurredAt: base.addingTimeInterval(60),
                deviceID: deviceA,
                lamport: 2,
                schemaVersion: 1
            )
        )

        clock.now = base.addingTimeInterval(100)
        await controller.reload()
        #expect(controller.totalSpent == 60)

        await controller.excludeSession(sessionID: sessionID)
        #expect(controller.totalSpent == 0)
        #expect(controller.entries.count == 1)
        #expect(controller.entries[0].isExcluded)

        await controller.includeSession(sessionID: sessionID)
        #expect(controller.totalSpent == 60)
        #expect(!controller.entries[0].isExcluded)
    }
}
