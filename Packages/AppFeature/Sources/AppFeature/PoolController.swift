import Foundation
import TaskDomain

public enum PoolShowMode: String, Sendable, CaseIterable, Identifiable {
    case today
    case allTasks
    case archived
    case completed

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .today: return "Today"
        case .allTasks: return "All Tasks"
        case .archived: return "Archived"
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
    public var showMode: PoolShowMode = .allTasks
    public var sortOrder: PoolSortOrder = .createdNewest

    public var visibleTasks: [Task] {
        let modeFiltered = tasks.filter { task in
            switch showMode {
            case .today:
                return !task.isCompleted && task.scheduledDay == DayKey.from(date: timeSource.now, calendar: calendar)
            case .allTasks:
                return !task.isCompleted
            case .archived, .completed:
                return task.isCompleted
            }
        }
        return filteredAndSorted(modeFiltered)
    }

    public var unscheduledTasks: [Task] {
        filteredAndSorted(tasks.filter { !$0.isCompleted && $0.scheduledDay == nil })
    }

    public func count(for mode: PoolShowMode) -> Int {
        tasks.filter { task in
            switch mode {
            case .today:
                return !task.isCompleted && task.scheduledDay == DayKey.from(date: timeSource.now, calendar: calendar)
            case .allTasks:
                return !task.isCompleted
            case .archived, .completed:
                return task.isCompleted
            }
        }.count
    }

    private let repository: any TaskRepository
    private let timeSource: any TimeSource
    private let calendar: Calendar

    private func filteredAndSorted(_ source: [Task]) -> [Task] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: [Task]
        if query.isEmpty { filtered = source }
        else { filtered = source.filter { $0.title.localizedCaseInsensitiveContains(query) } }
        return Self.sorted(filtered, by: sortOrder)
    }

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
            tasks = try await repository.allTasks()
        } catch {
            tasks = []
        }
    }

    public func quickAdd(title: String) async {
        do {
            if try await existingActiveTask(titled: title) != nil {
                showMode = .allTasks
                await reload()
                return
            }

            let created = try TaskService.create(title: title, now: timeSource.now)
            try await repository.upsert(created)
            showMode = .allTasks
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

    public func archive(_ task: Task) async {
        do {
            let archived = try TaskService.complete(task, now: timeSource.now)
            try await repository.upsert(archived)
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

    private func existingActiveTask(titled title: String) async throws -> Task? {
        let target = Self.normalizedTitle(title)
        guard !target.isEmpty else { return nil }
        return try await repository.allTasks().first {
            $0.completedAt == nil && Self.normalizedTitle($0.title) == target
        }
    }

    private static func normalizedTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    }
}
