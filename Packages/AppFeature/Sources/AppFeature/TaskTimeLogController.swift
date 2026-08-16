import Foundation
import AppData
import TimerDomain

public struct TaskTimeLogEntry: Identifiable, Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case session(sessionID: UUID, statusLabel: String)
        case adjustment
    }

    public var id: UUID
    public var kind: Kind
    public var duration: TimeInterval
    public var occurredAt: Date
    public var note: String?
    /// Sessions only — when true, duration is omitted from `totalSpent`.
    public var isExcluded: Bool

    public init(
        id: UUID,
        kind: Kind,
        duration: TimeInterval,
        occurredAt: Date,
        note: String? = nil,
        isExcluded: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.duration = duration
        self.occurredAt = occurredAt
        self.note = note
        self.isExcluded = isExcluded
    }
}

@Observable
@MainActor
public final class TaskTimeLogController {
    public private(set) var entries: [TaskTimeLogEntry] = []
    public private(set) var totalSpent: TimeInterval = 0

    private let taskID: UUID
    private let timerEvents: any TimerEventRepository
    private let timeLog: any TaskTimeLogRepository
    private let timeSource: any TimeSource

    public init(
        taskID: UUID,
        timerEvents: any TimerEventRepository,
        timeLog: any TaskTimeLogRepository,
        timeSource: any TimeSource = SystemTimeSource()
    ) {
        self.taskID = taskID
        self.timerEvents = timerEvents
        self.timeLog = timeLog
        self.timeSource = timeSource
    }

    public func reload() async {
        do {
            let events = try await timerEvents.loadAllEvents()
            let adjustments = try await timeLog.adjustments(forTaskID: taskID)
            let exclusions = try await timeLog.exclusions(forTaskID: taskID)
            let excludedIDs = Set(exclusions.map(\.sessionID))
            let now = timeSource.now

            var built: [TaskTimeLogEntry] = []
            let index = SessionArbitration.startIndex(from: events)

            for start in index {
                let sessionEvents = events.filter { $0.sessionID == start.sessionID }
                guard let started = sessionEvents.first(where: {
                    $0.kind == TimerEventKind.started.rawValue
                }), started.relatedTaskID == taskID else {
                    continue
                }

                let cutoff = SessionArbitration.supersededAt(for: start.sessionID, in: index)
                let projection = TimerEngine.projectSession(
                    sessionID: start.sessionID,
                    from: events,
                    supersededAt: cutoff
                )
                let state = TimerCalculator.evaluateSession(projection, at: now)
                // `.reset` discards history — omit from the log.
                if case .idle = state { continue }

                let duration = TimerCalculator.elapsed(projection, at: now)
                let statusLabel: String
                switch state {
                case .active(_, let phase):
                    statusLabel = phase == .paused ? "Paused" : "Running"
                case .completed(_, let reason):
                    switch reason {
                    case .expired: statusLabel = "Completed"
                    case .stoppedEarly: statusLabel = "Stopped"
                    case .superseded: statusLabel = "Superseded"
                    }
                case .idle:
                    continue
                }

                built.append(
                    TaskTimeLogEntry(
                        id: start.sessionID,
                        kind: .session(sessionID: start.sessionID, statusLabel: statusLabel),
                        duration: duration,
                        occurredAt: start.startedAt,
                        isExcluded: excludedIDs.contains(start.sessionID)
                    )
                )
            }

            for adjustment in adjustments {
                built.append(
                    TaskTimeLogEntry(
                        id: adjustment.id,
                        kind: .adjustment,
                        duration: adjustment.durationSeconds,
                        occurredAt: adjustment.occurredAt,
                        note: adjustment.note,
                        isExcluded: false
                    )
                )
            }

            entries = built.sorted { $0.occurredAt > $1.occurredAt }
            totalSpent = entries.reduce(0) { sum, entry in
                entry.isExcluded ? sum : sum + entry.duration
            }
        } catch {
            entries = []
            totalSpent = 0
        }
    }

    public func addAdjustment(durationSeconds: TimeInterval, note: String?) async {
        guard durationSeconds > 0 else { return }
        let now = timeSource.now
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let adjustment = TaskTimeAdjustment(
            taskID: taskID,
            durationSeconds: durationSeconds,
            note: (trimmed?.isEmpty == false) ? trimmed : nil,
            occurredAt: now,
            createdAt: now,
            updatedAt: now
        )
        do {
            try await timeLog.upsertAdjustment(adjustment)
            await reload()
        } catch { return }
    }

    public func editAdjustment(id: UUID, durationSeconds: TimeInterval, note: String?) async {
        guard durationSeconds > 0 else { return }
        do {
            let existing = try await timeLog.adjustments(forTaskID: taskID).first { $0.id == id }
            guard var adjustment = existing else { return }
            let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
            adjustment.durationSeconds = durationSeconds
            adjustment.note = (trimmed?.isEmpty == false) ? trimmed : nil
            adjustment.updatedAt = timeSource.now
            try await timeLog.upsertAdjustment(adjustment)
            await reload()
        } catch { return }
    }

    public func deleteAdjustment(id: UUID) async {
        do {
            try await timeLog.deleteAdjustment(id: id)
            await reload()
        } catch { return }
    }

    public func excludeSession(sessionID: UUID) async {
        let exclusion = TaskSessionExclusion(
            taskID: taskID,
            sessionID: sessionID,
            createdAt: timeSource.now
        )
        do {
            try await timeLog.upsertExclusion(exclusion)
            await reload()
        } catch { return }
    }

    public func includeSession(sessionID: UUID) async {
        do {
            try await timeLog.deleteExclusion(taskID: taskID, sessionID: sessionID)
            await reload()
        } catch { return }
    }
}

extension TaskTimeLogController {
    /// Formats a duration as `h:mm:ss` or `m:ss`.
    public static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
