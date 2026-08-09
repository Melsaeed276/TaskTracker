import Testing
import Foundation
import AppData
import TimerDomain
@testable import AppFeature

private struct FixedTimeSource: TimeSource {
    let now: Date
}

@Suite("ActiveTimerController")
struct ActiveTimerControllerTests {
    @Test("starts in idle state")
    @MainActor
    func initialStateIsIdle() async throws {
        let container = try AppDataModelContainer.makeLocalInMemory()
        let repo = SwiftDataTimerEventRepository(modelContainer: container)
        let controller = ActiveTimerController(repository: repo)

        await controller.reload()
        #expect(controller.state == .idle)
    }

    @Test("start transitions to active running")
    @MainActor
    func startTransitionsToActive() async throws {
        let container = try AppDataModelContainer.makeLocalInMemory()
        let repo = SwiftDataTimerEventRepository(modelContainer: container)
        let fixedDate = Date(timeIntervalSince1970: 1_000_000)
        let time = FixedTimeSource(now: fixedDate)
        let controller = ActiveTimerController(repository: repo, timeSource: time)

        await controller.start()

        guard case .active(_, let phase) = controller.state else {
            Issue.record("Expected .active, got \(controller.state)")
            return
        }
        #expect(phase == .running(since: fixedDate))
    }

    @Test("pause transitions to active paused")
    @MainActor
    func pauseTransitionsToPaused() async throws {
        let container = try AppDataModelContainer.makeLocalInMemory()
        let repo = SwiftDataTimerEventRepository(modelContainer: container)
        let controller = ActiveTimerController(
            repository: repo,
            timeSource: FixedTimeSource(now: Date(timeIntervalSince1970: 1_000_000))
        )

        await controller.start()
        await controller.pause()

        guard case .active(_, let phase) = controller.state else {
            Issue.record("Expected .active, got \(controller.state)")
            return
        }
        #expect(phase == .paused)
    }

    @Test("resume transitions back to active running")
    @MainActor
    func resumeTransitionsToRunning() async throws {
        let container = try AppDataModelContainer.makeLocalInMemory()
        let repo = SwiftDataTimerEventRepository(modelContainer: container)
        let fixedDate = Date(timeIntervalSince1970: 1_000_000)
        let time = FixedTimeSource(now: fixedDate)
        let controller = ActiveTimerController(repository: repo, timeSource: time)

        await controller.start()
        await controller.pause()
        await controller.resume()

        guard case .active(_, let phase) = controller.state else {
            Issue.record("Expected .active, got \(controller.state)")
            return
        }
        #expect(phase == .running(since: fixedDate))
    }

    @Test("stop transitions to idle")
    @MainActor
    func stopTransitionsToIdle() async throws {
        let container = try AppDataModelContainer.makeLocalInMemory()
        let repo = SwiftDataTimerEventRepository(modelContainer: container)
        let controller = ActiveTimerController(
            repository: repo,
            timeSource: FixedTimeSource(now: Date(timeIntervalSince1970: 1_000_000))
        )

        await controller.start()
        await controller.stop()

        #expect(controller.state == .idle)
    }

    @Test("full lifecycle: start, pause, resume, stop")
    @MainActor
    func fullLifecycle() async throws {
        let container = try AppDataModelContainer.makeLocalInMemory()
        let repo = SwiftDataTimerEventRepository(modelContainer: container)
        let fixedDate = Date(timeIntervalSince1970: 1_000_000)
        let time = FixedTimeSource(now: fixedDate)
        let controller = ActiveTimerController(repository: repo, timeSource: time)

        await controller.start()
        if case .active(_, let phase) = controller.state {
            #expect(phase == .running(since: fixedDate))
        } else {
            Issue.record("Expected .active after start")
            return
        }

        await controller.pause()
        if case .active(_, let phase) = controller.state {
            #expect(phase == .paused)
        } else {
            Issue.record("Expected .active after pause")
            return
        }

        await controller.resume()
        if case .active(_, let phase) = controller.state {
            #expect(phase == .running(since: fixedDate))
        } else {
            Issue.record("Expected .active after resume")
            return
        }

        await controller.stop()
        #expect(controller.state == .idle)
    }
}
