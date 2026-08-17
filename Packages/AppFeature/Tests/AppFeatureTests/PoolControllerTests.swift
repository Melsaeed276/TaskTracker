import Foundation
import Testing
import AppData
import TaskDomain
@testable import AppFeature

private struct FixedTimeSource: TimeSource {
    let now: Date
}

@Suite("PoolController")
struct PoolControllerTests {
    @MainActor
    private func makeController() throws -> (PoolController, SwiftDataTaskRepository, FixedTimeSource) {
        let container = try AppDataModelContainer.makeLocalInMemory()
        let repo = SwiftDataTaskRepository(modelContainer: container)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = FixedTimeSource(now: Date(timeIntervalSince1970: 1_700_000_000))
        let controller = PoolController(
            repository: repo,
            timeSource: now,
            calendar: calendar
        )
        return (controller, repo, now)
    }

    @Test("starts empty")
    @MainActor
    func initialStateIsEmpty() async throws {
        let (controller, _, _) = try makeController()
        await controller.reload()
        #expect(controller.tasks.isEmpty)
        #expect(controller.visibleTasks.isEmpty)
    }

    @Test("quick-add puts a task in the pool")
    @MainActor
    func quickAddToPool() async throws {
        let (controller, _, _) = try makeController()
        await controller.quickAdd(title: "Someday")

        #expect(controller.tasks.count == 1)
        #expect(controller.tasks[0].title == "Someday")
        #expect(controller.tasks[0].scheduledDay == nil)
        #expect(controller.tasks[0].completedAt == nil)
        #expect(controller.tasks[0].isInPool)
    }

    @Test("search filters pool tasks by title")
    @MainActor
    func searchFiltersByTitle() async throws {
        let (controller, _, _) = try makeController()
        await controller.quickAdd(title: "Alpha")
        await controller.quickAdd(title: "Beta")

        controller.searchText = "alp"
        #expect(controller.visibleTasks.count == 1)
        #expect(controller.visibleTasks[0].title == "Alpha")

        controller.searchText = ""
        #expect(controller.visibleTasks.count == 2)
    }

    @Test("search handles special characters and emoji queries")
    @MainActor
    func searchHandlesSpecialCharactersAndEmoji() async throws {
        let (controller, _, _) = try makeController()
        await controller.quickAdd(title: "Fix #123")
        await controller.quickAdd(title: "Coffee ☕️")
        await controller.quickAdd(title: "Plain task")

        controller.searchText = "#123"
        #expect(controller.visibleTasks.count == 1)
        #expect(controller.visibleTasks[0].title == "Fix #123")

        controller.searchText = "  ☕️  "
        #expect(controller.visibleTasks.count == 1)
        #expect(controller.visibleTasks[0].title == "Coffee ☕️")
    }

    @Test("scheduleForToday keeps the active task in the pool")
    @MainActor
    func scheduleForTodayLeavesPool() async throws {
        let (controller, _, _) = try makeController()
        await controller.quickAdd(title: "Do today")
        let task = try #require(controller.tasks.first)

        await controller.scheduleForToday(task)
        #expect(controller.tasks.count == 1)
        #expect(controller.tasks[0].scheduledDay == DayKey(rawValue: "2023-11-14"))
    }

    @Test("quick-add does not duplicate an active task title")
    @MainActor
    func quickAddDoesNotDuplicateActiveTitle() async throws {
        let (controller, _, _) = try makeController()
        await controller.quickAdd(title: "  Renew license  ")
        await controller.quickAdd(title: "renew LICENSE")

        #expect(controller.tasks.count == 1)
        #expect(controller.tasks[0].title == "Renew license")
    }

    @Test("archive removes the task from active pool")
    @MainActor
    func archiveRemovesTaskFromActivePool() async throws {
        let (controller, _, _) = try makeController()
        await controller.quickAdd(title: "Archive me")
        let task = try #require(controller.tasks.first)

        await controller.archive(task)
        #expect(controller.visibleTasks.isEmpty)
    }

    @Test("delete removes the task")
    @MainActor
    func deleteRemovesTask() async throws {
        let (controller, _, _) = try makeController()
        await controller.quickAdd(title: "Drop me")
        let task = try #require(controller.tasks.first)

        await controller.delete(task)
        #expect(controller.tasks.isEmpty)
    }

    @Test("edit updates title and notes")
    @MainActor
    func editTitleAndNotes() async throws {
        let (controller, _, _) = try makeController()
        await controller.quickAdd(title: "Draft")
        let task = try #require(controller.tasks.first)

        await controller.edit(task, title: "Draft v2", notes: "Later")
        let edited = try #require(controller.tasks.first)
        #expect(edited.title == "Draft v2")
        #expect(edited.notes == "Later")
        #expect(edited.scheduledDay == nil)
    }

    @Test("edit rejects an empty trimmed title and keeps the existing pool task unchanged")
    @MainActor
    func editRejectsEmptyTrimmedTitle() async throws {
        let (controller, _, _) = try makeController()
        await controller.quickAdd(title: "Original")
        let task = try #require(controller.tasks.first)

        await controller.edit(task, title: "   \n", notes: "Should not save")
        let unchanged = try #require(controller.tasks.first)
        #expect(unchanged.title == "Original")
        #expect(unchanged.notes == nil)
    }

    @Test("completed filter lists finished tasks; title sort is stable")
    @MainActor
    func completedFilterAndTitleSort() async throws {
        let (controller, repo, time) = try makeController()
        await controller.quickAdd(title: "Zebra")
        await controller.quickAdd(title: "Alpha")

        let zebra = try #require(controller.tasks.first { $0.title == "Zebra" })
        let alpha = try #require(controller.tasks.first { $0.title == "Alpha" })
        try await repo.upsert(try TaskService.complete(zebra, now: time.now))
        try await repo.upsert(try TaskService.complete(alpha, now: time.now.addingTimeInterval(1)))

        controller.showMode = .completed
        await controller.reload()
        #expect(controller.tasks.count == 2)

        controller.sortOrder = .title
        #expect(controller.visibleTasks.map(\.title) == ["Alpha", "Zebra"])

        await controller.uncomplete(controller.visibleTasks[0])
        controller.showMode = .allTasks
        await controller.reload()
        #expect(controller.tasks.contains { $0.title == "Alpha" })
    }

    @Test("pool cards filter today, all tasks, archived, and completed")
    @MainActor
    func cardFilters() async throws {
        let (controller, repo, time) = try makeController()
        await controller.quickAdd(title: "Inbox")
        await controller.quickAdd(title: "Today")
        await controller.quickAdd(title: "Done")

        let today = try #require(controller.tasks.first { $0.title == "Today" })
        let done = try #require(controller.tasks.first { $0.title == "Done" })
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        try await repo.upsert(TaskService.scheduleForToday(today, now: time.now, calendar: calendar))
        try await repo.upsert(try TaskService.complete(done, now: time.now))
        await controller.reload()

        controller.showMode = .today
        #expect(controller.visibleTasks.map(\.title) == ["Today"])

        controller.showMode = .allTasks
        #expect(controller.visibleTasks.map(\.title).sorted() == ["Inbox", "Today"])

        controller.showMode = .archived
        #expect(controller.visibleTasks.map(\.title) == ["Done"])

        controller.showMode = .completed
        #expect(controller.visibleTasks.map(\.title) == ["Done"])
    }

    @Test("unscheduled tasks preserve macOS Pool semantics")
    @MainActor
    func unscheduledTasks() async throws {
        let (controller, repo, time) = try makeController()
        await controller.quickAdd(title: "Inbox")
        await controller.quickAdd(title: "Today")

        let today = try #require(controller.tasks.first { $0.title == "Today" })
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        try await repo.upsert(TaskService.scheduleForToday(today, now: time.now, calendar: calendar))
        await controller.reload()

        #expect(controller.unscheduledTasks.map(\.title) == ["Inbox"])
    }
}
