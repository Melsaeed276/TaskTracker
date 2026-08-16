import Testing
import Foundation
import AppData
import TimerDomain
@testable import AppFeature

private struct FixedTimeSource: TimeSource {
    let now: Date
}

// `@unchecked Sendable`: confined to a single `@MainActor` test function each use, never shared
// across tasks/threads — matches how `SystemTimeSource` and `TimelineView`'s `context.date` agree
// on wall-clock time together in production (see `reloadIfExpired`'s doc comment).
private final class MutableTimeSource: TimeSource, @unchecked Sendable {
    var now: Date
    init(now: Date) { self.now = now }
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
        #expect(controller.compactLabel == nil)
    }

    @Test("start with relatedTaskID stores the task link on the session")
    @MainActor
    func startLinksRelatedTaskID() async throws {
        let container = try AppDataModelContainer.makeLocalInMemory()
        let repo = SwiftDataTimerEventRepository(modelContainer: container)
        let controller = ActiveTimerController(
            repository: repo,
            timeSource: FixedTimeSource(now: Date(timeIntervalSince1970: 1_000_000))
        )
        let taskID = UUID()

        await controller.start(duration: 60, relatedTaskID: taskID)

        guard case .active(let session, _) = controller.state else {
            Issue.record("Expected .active, got \(controller.state)")
            return
        }
        #expect(session.relatedTaskID == taskID)
        #expect(controller.relatedTaskID == taskID)
        #expect(controller.isLinked(toTaskID: taskID))
        #expect(!controller.isLinked(toTaskID: UUID()))
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
        #expect(controller.compactLabel == nil)
    }

    @Test("rapid start followed by immediate stop converges to idle")
    @MainActor
    func rapidStartThenImmediateStop() async throws {
        let container = try AppDataModelContainer.makeLocalInMemory()
        let repo = SwiftDataTimerEventRepository(modelContainer: container)
        let controller = ActiveTimerController(
            repository: repo,
            timeSource: FixedTimeSource(now: Date(timeIntervalSince1970: 1_000_000))
        )

        async let start: Void = controller.start(duration: 120)
        async let stop: Void = controller.stop()
        _ = await (start, stop)

        // If the stop raced before start authored its event, a second immediate stop should still
        // deterministically terminate the just-started session.
        await controller.stop()
        #expect(controller.state == .idle)
    }

    @Test("reset transitions to idle and discards the session's elapsed time")
    @MainActor
    func resetTransitionsToIdle() async throws {
        let container = try AppDataModelContainer.makeLocalInMemory()
        let repo = SwiftDataTimerEventRepository(modelContainer: container)
        let controller = ActiveTimerController(
            repository: repo,
            timeSource: FixedTimeSource(now: Date(timeIntervalSince1970: 1_000_000))
        )

        await controller.start()
        await controller.reset()

        #expect(controller.state == .idle)
        #expect(controller.compactLabel == nil)

        let events = try await repo.loadAllEvents()
        #expect(events.contains { $0.kind == TimerEventKind.reset.rawValue })
        #expect(events.contains { $0.kind == TimerEventKind.started.rawValue })

        guard let session = events.first?.sessionID else {
            Issue.record("Expected at least one event")
            return
        }
        let projection = TimerEngine.projectSession(sessionID: session, from: events, supersededAt: nil)
        #expect(projection.session?.accumulatedActive == 0)
        #expect(projection.session?.terminalEvent == .reset(at: Date(timeIntervalSince1970: 1_000_000)))
    }

    @Test("reset is a no-op when idle")
    @MainActor
    func resetWhileIdleIsNoOp() async throws {
        let container = try AppDataModelContainer.makeLocalInMemory()
        let repo = SwiftDataTimerEventRepository(modelContainer: container)
        let controller = ActiveTimerController(
            repository: repo,
            timeSource: FixedTimeSource(now: Date(timeIntervalSince1970: 1_000_000))
        )

        await controller.reload()
        await controller.reset()

        #expect(controller.state == .idle)
        #expect(try await repo.loadAllEvents().isEmpty)
    }

    @Test("reset is withheld from a quarantined session, which stays stoppable")
    @MainActor
    func resetWithheldWhileQuarantined() async throws {
        let container = try AppDataModelContainer.makeLocalInMemory()
        let repo = SwiftDataTimerEventRepository(modelContainer: container)
        let fixedDate = Date(timeIntervalSince1970: 1_000_000)
        let controller = ActiveTimerController(
            repository: repo,
            timeSource: FixedTimeSource(now: fixedDate)
        )

        await controller.start()
        guard case .active(let session, _) = controller.state else {
            Issue.record("Expected .active after start")
            return
        }

        try await repo.append(
            TimerEvent(
                id: UUID(),
                sessionID: session.id,
                kind: "future.noop",
                occurredAt: fixedDate,
                deviceID: UUID(),
                lamport: 99,
                schemaVersion: 1
            )
        )

        await controller.reset()
        guard case .active = controller.state else {
            Issue.record("Expected reset to be withheld, got \(controller.state)")
            return
        }
        let afterReset = try await repo.loadAllEvents()
        #expect(!afterReset.contains { $0.kind == TimerEventKind.reset.rawValue })

        await controller.stop()
        #expect(controller.state == .idle)
    }

    @Test("pause is withheld from a quarantined session, which stays stoppable")
    @MainActor
    func pauseWithheldWhileQuarantined() async throws {
        let container = try AppDataModelContainer.makeLocalInMemory()
        let repo = SwiftDataTimerEventRepository(modelContainer: container)
        let fixedDate = Date(timeIntervalSince1970: 1_000_000)
        let controller = ActiveTimerController(
            repository: repo,
            timeSource: FixedTimeSource(now: fixedDate)
        )

        await controller.start()
        guard case .active(let session, let phase) = controller.state, case .running = phase else {
            Issue.record("Expected .active(.running) after start")
            return
        }

        try await repo.append(
            TimerEvent(
                id: UUID(),
                sessionID: session.id,
                kind: "future.noop",
                occurredAt: fixedDate,
                deviceID: UUID(),
                lamport: 99,
                schemaVersion: 1
            )
        )

        await controller.pause()
        guard case .active(_, let phaseAfter) = controller.state, case .running = phaseAfter else {
            Issue.record("Expected pause to be withheld, got \(controller.state)")
            return
        }
        let afterPause = try await repo.loadAllEvents()
        #expect(!afterPause.contains { $0.kind == TimerEventKind.paused.rawValue })

        await controller.stop()
        #expect(controller.state == .idle)
    }

    @Test("resume is withheld from a quarantined session, which stays stoppable")
    @MainActor
    func resumeWithheldWhileQuarantined() async throws {
        let container = try AppDataModelContainer.makeLocalInMemory()
        let repo = SwiftDataTimerEventRepository(modelContainer: container)
        let fixedDate = Date(timeIntervalSince1970: 1_000_000)
        let controller = ActiveTimerController(
            repository: repo,
            timeSource: FixedTimeSource(now: fixedDate)
        )

        await controller.start()
        await controller.pause()
        guard case .active(let session, let phase) = controller.state, phase == .paused else {
            Issue.record("Expected .active(.paused) after pause")
            return
        }

        try await repo.append(
            TimerEvent(
                id: UUID(),
                sessionID: session.id,
                kind: "future.noop",
                occurredAt: fixedDate,
                deviceID: UUID(),
                lamport: 99,
                schemaVersion: 1
            )
        )

        await controller.resume()
        guard case .active(_, let phaseAfter) = controller.state, phaseAfter == .paused else {
            Issue.record("Expected resume to be withheld, got \(controller.state)")
            return
        }
        let afterResume = try await repo.loadAllEvents()
        #expect(!afterResume.contains { $0.kind == TimerEventKind.resumed.rawValue })

        await controller.stop()
        #expect(controller.state == .idle)
    }

    @Test("compactLabel is m:ss remaining while active")
    @MainActor
    func compactLabelWhileActive() async throws {
        let container = try AppDataModelContainer.makeLocalInMemory()
        let repo = SwiftDataTimerEventRepository(modelContainer: container)
        let controller = ActiveTimerController(
            repository: repo,
            timeSource: FixedTimeSource(now: Date(timeIntervalSince1970: 1_000_000))
        )

        await controller.start()
        #expect(controller.compactLabel == "25:00")

        await controller.pause()
        #expect(controller.compactLabel == "25:00")

        await controller.stop()
        #expect(controller.compactLabel == nil)
    }

    @Test("presentation labels format remaining, duration, elapsed, and end time")
    @MainActor
    func timerPresentationLabels() async throws {
        let container = try AppDataModelContainer.makeLocalInMemory()
        let repo = SwiftDataTimerEventRepository(modelContainer: container)
        let start = Date(timeIntervalSince1970: 1_000_000)
        let controller = ActiveTimerController(
            repository: repo,
            timeSource: FixedTimeSource(now: start)
        )

        await controller.start(duration: 3 * 60 * 60)

        let later = start.addingTimeInterval(3)
        #expect(controller.remainingListLabel(at: later) == "2:59:57")
        #expect(controller.sessionDurationLabel == "3 hr")
        #expect(controller.elapsedStopwatchDigital(at: start.addingTimeInterval(65.42)) == "01:05.42")
        #expect(controller.endTimeLabel(at: later)?.hasPrefix("Ends ") == true)
    }

    @Test("duration label uses minutes below one hour")
    @MainActor
    func durationLabelUsesMinutes() async throws {
        let container = try AppDataModelContainer.makeLocalInMemory()
        let repo = SwiftDataTimerEventRepository(modelContainer: container)
        let controller = ActiveTimerController(
            repository: repo,
            timeSource: FixedTimeSource(now: Date(timeIntervalSince1970: 1_000_000))
        )

        await controller.start(duration: 25 * 60)

        #expect(controller.sessionDurationLabel == "25 min")
        #expect(ActiveTimerController.durationLabel(for: 60) == "1 min")
        #expect(ActiveTimerController.durationLabel(for: 60 * 60) == "1 hr")
    }

    @Test("fire date shifts after pause and resume")
    @MainActor
    func fireDateShiftsAfterPauseResume() async throws {
        let container = try AppDataModelContainer.makeLocalInMemory()
        let repo = SwiftDataTimerEventRepository(modelContainer: container)
        let start = Date(timeIntervalSince1970: 1_000_000)
        let time = MutableTimeSource(now: start)
        let controller = ActiveTimerController(repository: repo, timeSource: time)

        await controller.start(duration: 25 * 60)
        #expect(controller.fireDate(at: start) == start.addingTimeInterval(25 * 60))

        time.now = start.addingTimeInterval(10 * 60)
        await controller.pause()
        #expect(controller.fireDate(at: time.now) == start.addingTimeInterval(25 * 60))

        time.now = start.addingTimeInterval(15 * 60)
        await controller.resume()
        #expect(controller.fireDate(at: time.now) == start.addingTimeInterval(30 * 60))
    }

    @Test("stopwatch hand angles follow elapsed time")
    @MainActor
    func stopwatchHandAnglesFollowElapsedTime() async throws {
        let container = try AppDataModelContainer.makeLocalInMemory()
        let repo = SwiftDataTimerEventRepository(modelContainer: container)
        let start = Date(timeIntervalSince1970: 1_000_000)
        let controller = ActiveTimerController(
            repository: repo,
            timeSource: FixedTimeSource(now: start)
        )

        await controller.start(duration: 60 * 60)

        let angles = controller.stopwatchHandAngles(at: start.addingTimeInterval(15 * 60 + 30))
        #expect(angles.seconds == 180)
        #expect(abs(angles.minutes - 186) < 0.0001)
    }

    @Test("reloadIfExpired transitions active timer to completed once its fire date passes")
    @MainActor
    func reloadIfExpiredTransitionsPastFireDate() async throws {
        let container = try AppDataModelContainer.makeLocalInMemory()
        let repo = SwiftDataTimerEventRepository(modelContainer: container)
        let time = MutableTimeSource(now: Date(timeIntervalSince1970: 1_000_000))
        let controller = ActiveTimerController(repository: repo, timeSource: time)

        await controller.start(duration: 60)
        guard case .active = controller.state else {
            Issue.record("Expected .active after start")
            return
        }

        // Not yet expired: no-op, state unchanged.
        time.now = time.now.addingTimeInterval(30)
        await controller.reloadIfExpired(at: time.now)
        guard case .active = controller.state else {
            Issue.record("Expected still .active before the fire date")
            return
        }

        // Past the fire date: TimelineView calling this every tick must flip state on its own,
        // matching how a ticking display and `timeSource.now` agree in production.
        time.now = time.now.addingTimeInterval(31)
        await controller.reloadIfExpired(at: time.now)
        guard case .completed(_, let reason) = controller.state else {
            Issue.record("Expected .completed after the fire date, got \(controller.state)")
            return
        }
        #expect(reason == .expired)
        #expect(controller.compactLabel == nil)
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
