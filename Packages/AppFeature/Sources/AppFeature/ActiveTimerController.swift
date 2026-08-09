import Foundation
import TimerDomain

@Observable
@MainActor
public final class ActiveTimerController {
    public private(set) var state: ActiveTimerState = .idle

    /// Human-readable description of the current state. All timer arithmetic lives here,
    /// not in SwiftUI views (see AGENTS.md).
    public var stateDescription: String {
        switch state {
        case .idle:
            return "Idle"
        case .active(_, let phase):
            switch phase {
            case .running(let since):
                let elapsed = timeSource.now.timeIntervalSince(since)
                let minutes = Int(elapsed) / 60
                let seconds = Int(elapsed) % 60
                return "Running \(minutes)m \(seconds)s"
            case .paused:
                return "Paused"
            }
        case .completed(_, let reason):
            switch reason {
            case .expired: return "Expired"
            case .stoppedEarly: return "Stopped"
            case .superseded: return "Superseded"
            }
        }
    }

    /// Whether the active timer is currently paused. Drives the Pause/Resume button label.
    public var isPaused: Bool {
        if case .active(_, let phase) = state, phase == .paused {
            return true
        }
        return false
    }

    private let repository: any TimerEventRepository
    private let timeSource: any TimeSource
    private let deviceID: UUID
    private var clock = LamportClock()
    private var currentSessionID: UUID?

    public init(
        repository: any TimerEventRepository,
        timeSource: any TimeSource = SystemTimeSource(),
        deviceID: UUID = UUID()
    ) {
        self.repository = repository
        self.timeSource = timeSource
        self.deviceID = deviceID
    }

    public func reload() async {
        do {
            let events = try await repository.loadAllEvents()
            for event in events {
                clock.observe(remoteValue: event.lamport)
            }
            state = TimerEngine.evaluateActiveTimer(events: events, at: timeSource.now)
        } catch {
            state = .idle
        }
    }

    public func start(duration: TimeInterval = 25 * 60) async {
        let events: [TimerEvent]
        do {
            events = try await repository.loadAllEvents()
        } catch { return }

        for event in events {
            clock.observe(remoteValue: event.lamport)
        }

        let sessionID = UUID()
        clock.tick()
        let event = TimerEvent(
            id: UUID(),
            sessionID: sessionID,
            kind: TimerEventKind.started.rawValue,
            occurredAt: timeSource.now,
            deviceID: deviceID,
            lamport: clock.value,
            schemaVersion: 1,
            duration: duration,
            relatedTaskID: nil
        )

        do {
            try await repository.append(event)
        } catch { return }

        currentSessionID = sessionID
        await reload()
    }

    public func pause() async {
        await reload()
        guard case .active(let session, let phase) = state,
              case .running = phase else { return }

        clock.tick()
        let event = TimerEvent(
            id: UUID(),
            sessionID: session.id,
            kind: TimerEventKind.paused.rawValue,
            occurredAt: timeSource.now,
            deviceID: deviceID,
            lamport: clock.value,
            schemaVersion: 1
        )

        do {
            try await repository.append(event)
        } catch { return }

        await reload()
    }

    public func resume() async {
        await reload()
        guard case .active(let session, let phase) = state,
              phase == .paused else { return }

        clock.tick()
        let event = TimerEvent(
            id: UUID(),
            sessionID: session.id,
            kind: TimerEventKind.resumed.rawValue,
            occurredAt: timeSource.now,
            deviceID: deviceID,
            lamport: clock.value,
            schemaVersion: 1
        )

        do {
            try await repository.append(event)
        } catch { return }

        await reload()
    }

    public func stop() async {
        await reload()
        guard case .active(let session, _) = state else { return }

        clock.tick()
        let event = TimerEvent(
            id: UUID(),
            sessionID: session.id,
            kind: TimerEventKind.stopped.rawValue,
            occurredAt: timeSource.now,
            deviceID: deviceID,
            lamport: clock.value,
            schemaVersion: 1
        )

        do {
            try await repository.append(event)
        } catch { return }

        await reload()
    }
}
