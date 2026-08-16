import Foundation
import Testing
import AppData
import TimerDomain
@testable import AppFeature

private struct FixedTimeSource: TimeSource {
    let now: Date
}

actor SpyTimerExpiryNotifier: TimerExpiryNotifying {
    private(set) var scheduledDates: [Date] = []
    private(set) var cancelCount = 0

    func scheduleExpiry(at fireDate: Date) async {
        scheduledDates.append(fireDate)
    }

    func cancelExpiry() async {
        cancelCount += 1
    }

    func snapshot() -> (scheduled: [Date], cancels: Int) {
        (scheduledDates, cancelCount)
    }
}

@Suite("ActiveTimerController expiry notifications")
struct ActiveTimerExpiryNotifierTests {
    private let fixedDate = Date(timeIntervalSince1970: 1_000_000)

    @MainActor
    private func makeController(
        notifier: SpyTimerExpiryNotifier
    ) async throws -> (ActiveTimerController, SpyTimerExpiryNotifier) {
        let container = try AppDataModelContainer.makeLocalInMemory()
        let repo = SwiftDataTimerEventRepository(modelContainer: container)
        let controller = ActiveTimerController(
            repository: repo,
            timeSource: FixedTimeSource(now: fixedDate),
            expiryNotifier: notifier
        )
        return (controller, notifier)
    }

    @Test("start schedules expiry at now + remaining")
    @MainActor
    func startSchedulesExpiry() async throws {
        let spy = SpyTimerExpiryNotifier()
        let (controller, _) = try await makeController(notifier: spy)
        let duration: TimeInterval = 25 * 60

        await controller.start(duration: duration)

        let snap = await spy.snapshot()
        #expect(snap.scheduled.count == 1)
        #expect(snap.scheduled[0] == fixedDate.addingTimeInterval(duration))
    }

    @Test("pause cancels the pending expiry")
    @MainActor
    func pauseCancelsExpiry() async throws {
        let spy = SpyTimerExpiryNotifier()
        let (controller, _) = try await makeController(notifier: spy)

        await controller.start()
        await controller.pause()

        let snap = await spy.snapshot()
        #expect(snap.scheduled.count >= 1)
        #expect(snap.cancels >= 1)
        guard case .active(_, let phase) = controller.state else {
            Issue.record("Expected paused active state")
            return
        }
        #expect(phase == .paused)
    }

    @Test("resume reschedules expiry from remaining")
    @MainActor
    func resumeReschedulesExpiry() async throws {
        let spy = SpyTimerExpiryNotifier()
        let (controller, _) = try await makeController(notifier: spy)
        let duration: TimeInterval = 30 * 60

        await controller.start(duration: duration)
        await controller.pause()
        await controller.resume()

        let snap = await spy.snapshot()
        #expect(snap.scheduled.count >= 2)
        #expect(snap.scheduled.last == fixedDate.addingTimeInterval(duration))
    }

    @Test("stop cancels the pending expiry")
    @MainActor
    func stopCancelsExpiry() async throws {
        let spy = SpyTimerExpiryNotifier()
        let (controller, _) = try await makeController(notifier: spy)

        await controller.start()
        await controller.stop()

        let snap = await spy.snapshot()
        #expect(snap.cancels >= 1)
        #expect(controller.state == .idle)
    }

    @Test("reset cancels the pending expiry")
    @MainActor
    func resetCancelsExpiry() async throws {
        let spy = SpyTimerExpiryNotifier()
        let (controller, _) = try await makeController(notifier: spy)

        await controller.start()
        let beforeReset = await spy.snapshot()

        await controller.reset()

        let snap = await spy.snapshot()
        #expect(snap.cancels > beforeReset.cancels)
        #expect(controller.state == .idle)
    }
}
