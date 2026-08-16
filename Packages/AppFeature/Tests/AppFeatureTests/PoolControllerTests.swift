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

    @Test("scheduleForToday removes the task from the pool")
    @MainActor
    func scheduleForTodayLeavesPool() async throws {
        let (controller, _, _) = try makeController()
        await controller.quickAdd(title: "Do today")
        let task = try #require(controller.tasks.first)

        await controller.scheduleForToday(task)
        #expect(controller.tasks.isEmpty)
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
        controller.showMode = .active
        await controller.reload()
        #expect(controller.tasks.contains { $0.title == "Alpha" })
    }
}
