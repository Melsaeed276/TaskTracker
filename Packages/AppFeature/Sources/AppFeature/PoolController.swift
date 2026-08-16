import Foundation
import TaskDomain

public enum PoolShowMode: String, Sendable, CaseIterable, Identifiable {
    case active
    case completed

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .active: return "Active"
        case .completed: return "Completed"
        }
    }
}

public enum PoolSortOrder: String, Sendable, CaseIterable, Identifiable {
    case createdNewest
    case createdOldest
    case title
    case priority

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .createdNewest: return "Newest first"
        case .createdOldest: return "Oldest first"
        case .title: return "Title"
        case .priority: return "Priority"
        }
    }
}

@Observable
@MainActor
public final class PoolController {
    public private(set) var tasks: [Task] = []
    public var searchText: String = ""
    public var showMode: PoolShowMode = .active
    public var sortOrder: PoolSortOrder = .createdNewest

    public var visibleTasks: [Task] {
        let filtered: [Task]
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            filtered = tasks
        } else {
            filtered = tasks.filter { $0.title.localizedCaseInsensitiveContains(query) }
        }
        return Self.sorted(filtered, by: sortOrder)
    }

    private let repository: any TaskRepository
    private let timeSource: any TimeSource
    private let calendar: Calendar

    public init(
        repository: any TaskRepository,
        timeSource: any TimeSource = SystemTimeSource(),
        calendar: Calendar = .current
    ) {
        self.repository = repository
        self.timeSource = timeSource
        self.calendar = calendar
    }

    public func reload() async {
        do {
            switch showMode {
            case .active:
                tasks = try await repository.poolTasks()
            case .completed:
                tasks = try await repository.completedTasks()
            }
        } catch {
            tasks = []
        }
    }

    public func quickAdd(title: String) async {
        do {
            let created = try TaskService.create(title: title, now: timeSource.now)
            try await repository.upsert(created)
            showMode = .active
            await reload()
        } catch { return }
    }

    public func scheduleForToday(_ task: Task) async {
        do {
            let scheduled = TaskService.scheduleForToday(task, now: timeSource.now, calendar: calendar)
            try await repository.upsert(scheduled)
            await reload()
        } catch { return }
    }

    public func delete(_ task: Task) async {
        do {
            try await repository.deleteTask(id: task.id)
            await reload()
        } catch { return }
    }

    public func uncomplete(_ task: Task) async {
        do {
            let updated = TaskService.uncomplete(task, now: timeSource.now)
            try await repository.upsert(updated)
            await reload()
        } catch { return }
    }

    public func edit(
        _ task: Task,
        title: String,
        notes: String?,
        scheduledDay: DayKey? = nil,
        priority: TaskPriority = .none,
        applyScheduleAndPriority: Bool = false
    ) async {
        do {
            let updated = try TaskService.edit(
                task,
                title: title,
                notes: notes,
                now: timeSource.now,
                scheduledDay: scheduledDay,
                priority: priority,
                applyScheduleAndPriority: applyScheduleAndPriority
            )
            try await repository.upsert(updated)
            await reload()
        } catch { return }
    }

    private static func sorted(_ tasks: [Task], by order: PoolSortOrder) -> [Task] {
        switch order {
        case .createdNewest:
            return tasks.sorted { $0.createdAt > $1.createdAt }
        case .createdOldest:
            return tasks.sorted { $0.createdAt < $1.createdAt }
        case .title:
            return tasks.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .priority:
            return tasks.sorted {
                if $0.priority != $1.priority { return $0.priority > $1.priority }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }
    }
}
