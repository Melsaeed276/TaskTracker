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

    public var isActive: Bool {
        if case .active = state { return true }
        return false
    }

    /// Task linked on the active session's `.started` event, if any.
    public var relatedTaskID: UUID? {
        switch state {
        case .active(let session, _), .completed(let session, _):
            return session.relatedTaskID
        case .idle:
            return nil
        }
    }

    /// Whether the active session is linked to `taskID`.
    public func isLinked(toTaskID taskID: UUID) -> Bool {
        relatedTaskID == taskID && isActive
    }

    /// Compact `m:ss` countdown for the menu-bar label, or `nil` when idle/completed.
    /// Remaining time comes from `TimerCalculator`; this only formats it.
    public var compactLabel: String? {
        compactLabel(at: timeSource.now)
    }

    public func compactLabel(at date: Date) -> String? {
        guard case .active = state else { return nil }
        let remaining = Int(TimerCalculator.remaining(state, at: date))
        return String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    /// Apple Clock-style list row countdown: `h:mm:ss` once an hour remains, otherwise `m:ss`.
    public func remainingListLabel(at date: Date) -> String? {
        guard case .active = state else { return nil }
        let remaining = max(0, Int(TimerCalculator.remaining(state, at: date)))
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        let seconds = remaining % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Human preset label for the active session duration, such as `25 min` or `3 hr`.
    public var sessionDurationLabel: String? {
        guard case .active(let session, _) = state else { return nil }
        return Self.durationLabel(for: session.duration)
    }

    public static func durationLabel(for duration: TimeInterval) -> String {
        let totalMinutes = max(1, Int((duration / 60).rounded()))
        if totalMinutes.isMultiple(of: 60) {
            let hours = totalMinutes / 60
            return hours == 1 ? "1 hr" : "\(hours) hr"
        }
        return totalMinutes == 1 ? "1 min" : "\(totalMinutes) min"
    }

    /// Stopwatch-style elapsed text. This is presentation only over the countdown session.
    public func elapsedStopwatchDigital(at date: Date) -> String {
        let elapsed = elapsedSeconds(at: date)
        let totalCentiseconds = max(0, Int((elapsed * 100).rounded()))
        let minutes = totalCentiseconds / 6_000
        let seconds = (totalCentiseconds / 100) % 60
        let centiseconds = totalCentiseconds % 100
        return String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
    }

    /// Wall-clock finish label, derived from the same fire date used by notifications/live activity.
    public func endTimeLabel(at date: Date) -> String? {
        guard let fireDate = fireDate(at: date) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "Ends \(formatter.string(from: fireDate))"
    }

    public func stopwatchHandAngles(at date: Date) -> StopwatchHandAngles {
        let elapsed = elapsedSeconds(at: date)
        return StopwatchHandAngles(
            seconds: (elapsed.truncatingRemainder(dividingBy: 60) / 60) * 360,
            minutes: (elapsed.truncatingRemainder(dividingBy: 1_800) / 1_800) * 360
        )
    }

    /// Fire date is `date + remaining` from `TimerCalculator` — no second time-tracking path.
    public func fireDate(at date: Date) -> Date? {
        guard case .active = state else { return nil }
        let remaining = TimerCalculator.remaining(state, at: date)
        guard remaining > 0 else { return nil }
        return date.addingTimeInterval(remaining)
    }

    /// `state` only changes on an explicit `reload()` — a ticking `TimelineView` reformats the
    /// display every second but never re-evaluates on its own, so a timer that reaches its fire
    /// date stays stuck showing `.active` at `0:00` until some other action happens to reload.
    /// Views should call this on every tick; it only pays for a real `reload()` right at expiry.
    public func reloadIfExpired(at date: Date) async {
        guard case .active = state, TimerCalculator.remaining(state, at: date) <= 0 else { return }
        await reload()
    }

    private let repository: any TimerEventRepository
    private let timeSource: any TimeSource
    private let deviceID: UUID
    private let expiryNotifier: any TimerExpiryNotifying
    private let liveActivity: any TimerLiveActivityControlling
    private var clock = LamportClock()
    private var currentSessionID: UUID?

    public init(
        repository: any TimerEventRepository,
        timeSource: any TimeSource = SystemTimeSource(),
        deviceID: UUID = UUID(),
        expiryNotifier: any TimerExpiryNotifying = NoOpTimerExpiryNotifier(),
        liveActivity: any TimerLiveActivityControlling = NoOpTimerLiveActivityController()
    ) {
        self.repository = repository
        self.timeSource = timeSource
        self.deviceID = deviceID
        self.expiryNotifier = expiryNotifier
        self.liveActivity = liveActivity
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
        await syncExpiryNotification()
        await syncLiveActivity()
    }

    public func start(duration: TimeInterval = 25 * 60, relatedTaskID: UUID? = nil) async {
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
            relatedTaskID: relatedTaskID
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
        guard TimerAuthoringPolicy.isAuthorable(
            .paused,
            quarantined: session.quarantine.isQuarantined
        ) else { return }

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
        guard TimerAuthoringPolicy.isAuthorable(
            .resumed,
            quarantined: session.quarantine.isQuarantined
        ) else { return }

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

    /// Discards the session and its elapsed time from history. Withheld from a quarantined
    /// session, which must not have history it cannot interpret erased — `stop()` stays available
    /// there and always terminates the session (docs/TIMER_ARCHITECTURE.md).
    public func reset() async {
        await reload()
        guard case .active(let session, _) = state else { return }
        guard TimerAuthoringPolicy.isAuthorable(
            .reset,
            quarantined: session.quarantine.isQuarantined
        ) else { return }

        clock.tick()
        let event = TimerEvent(
            id: UUID(),
            sessionID: session.id,
            kind: TimerEventKind.reset.rawValue,
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

    private func syncExpiryNotification() async {
        switch state {
        case .active(_, .running):
            guard let fireDate = fireDate(at: timeSource.now) else {
                await expiryNotifier.cancelExpiry()
                return
            }
            await expiryNotifier.scheduleExpiry(at: fireDate)
        case .idle, .completed, .active(_, .paused):
            await expiryNotifier.cancelExpiry()
        }
    }

    /// Live Activity receives a fire date only — never a remaining-seconds value (AGENTS.md).
    private func syncLiveActivity() async {
        switch state {
        case .active(let session, .running):
            guard let fireDate = fireDate(at: timeSource.now) else {
                await liveActivity.sync(title: "Focus", fireDate: nil, isPaused: false)
                return
            }
            let title = session.relatedTaskID == nil ? "Focus" : "Focus · Task"
            await liveActivity.sync(
                title: title,
                fireDate: fireDate,
                isPaused: false
            )
        case .active(let session, .paused):
            let title = session.relatedTaskID == nil ? "Focus" : "Focus · Task"
            await liveActivity.sync(
                title: title,
                fireDate: fireDate(at: timeSource.now),
                isPaused: true
            )
        case .idle, .completed:
            await liveActivity.sync(title: "Focus", fireDate: nil, isPaused: false)
        }
    }

    private func elapsedSeconds(at date: Date) -> TimeInterval {
        switch state {
        case .idle:
            return 0
        case .active(let session, let phase):
            let runningExtra: TimeInterval
            if case .running(let since) = phase {
                runningExtra = max(0, date.timeIntervalSince(since))
            } else {
                runningExtra = 0
            }
            return max(0, session.accumulatedActive + runningExtra)
        case .completed(let session, _):
            return max(0, session.accumulatedActive)
        }
    }
}

public struct StopwatchHandAngles: Sendable, Equatable {
    public var seconds: Double
    public var minutes: Double

    public init(seconds: Double, minutes: Double) {
        self.seconds = seconds
        self.minutes = minutes
    }
}
