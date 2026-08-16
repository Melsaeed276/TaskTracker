import Foundation
import Testing
import AppData
import TimerDomain
@testable import AppFeature

private struct FixedTimeSource: TimeSource {
    let now: Date
}

actor SpyTimerLiveActivityController: TimerLiveActivityControlling {
    struct Call: Equatable {
        var title: String
        var fireDate: Date?
        var isPaused: Bool
    }

    private(set) var calls: [Call] = []

    func sync(title: String, fireDate: Date?, isPaused: Bool) async {
        calls.append(Call(title: title, fireDate: fireDate, isPaused: isPaused))
    }

    func snapshot() -> [Call] { calls }
}

@Suite("ActiveTimerController Live Activity")
struct ActiveTimerLiveActivityTests {
    private let fixedDate = Date(timeIntervalSince1970: 1_000_000)

    @Test("start syncs a fire date, never remaining seconds alone")
    @MainActor
    func startSyncsFireDate() async throws {
        let spy = SpyTimerLiveActivityController()
        let container = try AppDataModelContainer.makeLocalInMemory()
        let repo = SwiftDataTimerEventRepository(modelContainer: container)
        let controller = ActiveTimerController(
            repository: repo,
            timeSource: FixedTimeSource(now: fixedDate),
            liveActivity: spy
        )
        let duration: TimeInterval = 25 * 60

        await controller.start(duration: duration)

        let calls = await spy.snapshot()
        let last = try #require(calls.last)
        #expect(last.fireDate == fixedDate.addingTimeInterval(duration))
        #expect(last.isPaused == false)
        #expect(last.title == "Focus")
    }

    @Test("stop ends the Live Activity")
    @MainActor
    func stopEndsLiveActivity() async throws {
        let spy = SpyTimerLiveActivityController()
        let container = try AppDataModelContainer.makeLocalInMemory()
        let repo = SwiftDataTimerEventRepository(modelContainer: container)
        let controller = ActiveTimerController(
            repository: repo,
            timeSource: FixedTimeSource(now: fixedDate),
            liveActivity: spy
        )

        await controller.start(duration: 60)
        await controller.stop()

        let calls = await spy.snapshot()
        let last = try #require(calls.last)
        #expect(last.fireDate == nil)
    }

    @Test("start while paused supersedes and syncs a new Live Activity fire date")
    @MainActor
    func startWhilePausedSupersedes() async throws {
        let spy = SpyTimerLiveActivityController()
        let container = try AppDataModelContainer.makeLocalInMemory()
        let repo = SwiftDataTimerEventRepository(modelContainer: container)
        let clock = AdjustableTimeSource(now: fixedDate)
        let controller = ActiveTimerController(
            repository: repo,
            timeSource: clock,
            liveActivity: spy
        )

        await controller.start(duration: 120)
        clock.now = fixedDate.addingTimeInterval(5)
        await controller.pause()
        #expect(controller.isPaused)

        let taskID = UUID()
        clock.now = fixedDate.addingTimeInterval(10)
        await controller.start(duration: 60, relatedTaskID: taskID)

        #expect(controller.isActive)
        #expect(!controller.isPaused)
        let calls = await spy.snapshot()
        let last = try #require(calls.last)
        #expect(last.fireDate == clock.now.addingTimeInterval(60))
        #expect(last.isPaused == false)
        #expect(last.title == "Focus · Task")
    }
}

private final class AdjustableTimeSource: TimeSource, @unchecked Sendable {
    var now: Date
    init(now: Date) { self.now = now }
}
