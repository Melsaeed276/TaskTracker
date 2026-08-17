import Foundation
import Testing
import AppData
import TaskDomain
@testable import AppFeature

private struct FixedTimeSource: TimeSource {
    let now: Date
}

@Suite("TodayController")
struct TodayControllerTests {
    @MainActor
    private func makeController() throws -> (TodayController, SwiftDataTaskRepository) {
        let container = try AppDataModelContainer.makeLocalInMemory()
        let repo = SwiftDataTaskRepository(modelContainer: container)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let controller = TodayController(
            repository: repo,
            timeSource: FixedTimeSource(now: now),
            calendar: calendar
        )
        return (controller, repo)
    }

    @Test("starts empty")
    @MainActor
    func initialStateIsEmpty() async throws {
        let (controller, _) = try makeController()
        await controller.reload()
        #expect(controller.tasks.isEmpty)
    }

    @Test("quick-add schedules a task for today")
    @MainActor
    func quickAddSchedulesForToday() async throws {
        let (controller, _) = try makeController()
        await controller.quickAdd(title: "Write tests")

        #expect(controller.tasks.count == 1)
        #expect(controller.tasks[0].title == "Write tests")
        #expect(controller.tasks[0].scheduledDay == DayKey(rawValue: "2023-11-14"))
        #expect(controller.tasks[0].completedAt == nil)
    }

    @Test("quick-add schedules an existing active task instead of duplicating it")
    @MainActor
    func quickAddSchedulesExistingActiveTask() async throws {
        let (controller, repo) = try makeController()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let existing = try TaskService.create(title: "Call bank", now: now)
        try await repo.upsert(existing)

        await controller.quickAdd(title: "  call BANK  ")

        #expect(controller.tasks.count == 1)
        #expect(controller.tasks[0].id == existing.id)
        #expect(controller.tasks[0].scheduledDay == DayKey(rawValue: "2023-11-14"))
        #expect(try await repo.allTasks().count == 1)
    }

    @Test("removeFromToday clears schedule without completing")
    @MainActor
    func removeFromTodayClearsSchedule() async throws {
        let (controller, repo) = try makeController()
        await controller.quickAdd(title: "Move back")
        let task = try #require(controller.tasks.first)

        await controller.removeFromToday(task)

        #expect(controller.tasks.isEmpty)
        let stored = try #require(try await repo.task(id: task.id))
        #expect(stored.scheduledDay == nil)
        #expect(stored.completedAt == nil)
    }

    @Test("complete removes the task from Today; uncomplete restores it")
    @MainActor
    func completeRemovesFromToday() async throws {
        let (controller, repo) = try makeController()
        await controller.quickAdd(title: "Ship it")
        let task = try #require(controller.tasks.first)

        await controller.complete(task)
        #expect(controller.tasks.isEmpty)

        let completed = try await repo.completedTasks()
        #expect(completed.count == 1)
        #expect(completed[0].completedAt != nil)

        await controller.uncomplete(completed[0])
        #expect(controller.tasks.count == 1)
        #expect(controller.tasks[0].completedAt == nil)
    }

    @Test("delete removes the task from Today")
    @MainActor
    func deleteRemovesTask() async throws {
        let (controller, _) = try makeController()
        await controller.quickAdd(title: "Gone")
        let task = try #require(controller.tasks.first)
        await controller.delete(task)
        #expect(controller.tasks.isEmpty)
    }

    @Test("edit updates title, notes, schedule, and priority")
    @MainActor
    func editTitleNotesScheduleAndPriority() async throws {
        let (controller, _) = try makeController()
        await controller.quickAdd(title: "Draft")
        let task = try #require(controller.tasks.first)

        await controller.edit(
            task,
            title: "Draft v2",
            notes: "Ship notes",
            scheduledDay: nil,
            priority: .high,
            applyScheduleAndPriority: true
        )
        #expect(controller.tasks.isEmpty)

        await controller.quickAdd(title: "Back")
        let again = try #require(controller.tasks.first)
        await controller.edit(
            again,
            title: "Back",
            notes: nil,
            scheduledDay: DayKey(rawValue: "2023-11-14"),
            priority: .medium,
            applyScheduleAndPriority: true
        )
        let edited = try #require(controller.tasks.first)
        #expect(edited.title == "Back")
        #expect(edited.priority == .medium)
        #expect(edited.scheduledDay == DayKey(rawValue: "2023-11-14"))
    }

    @Test("edit updates title and notes")
    @MainActor
    func editTitleAndNotes() async throws {
        let (controller, _) = try makeController()
        await controller.quickAdd(title: "Draft")
        let task = try #require(controller.tasks.first)

        await controller.edit(task, title: "Draft v2", notes: "Ship notes")
        let edited = try #require(controller.tasks.first)
        #expect(edited.title == "Draft v2")
        #expect(edited.notes == "Ship notes")
    }

    @Test("edit rejects an empty trimmed title and keeps the existing task unchanged")
    @MainActor
    func editRejectsEmptyTrimmedTitle() async throws {
        let (controller, _) = try makeController()
        await controller.quickAdd(title: "Original")
        let task = try #require(controller.tasks.first)

        await controller.edit(task, title: "   \n\t", notes: "Should not save")
        let unchanged = try #require(controller.tasks.first)
        #expect(unchanged.title == "Original")
        #expect(unchanged.notes == nil)
    }

    @Test("empty title is rejected")
    @MainActor
    func emptyTitleRejected() async throws {
        let (controller, _) = try makeController()
        await controller.quickAdd(title: "   ")
        #expect(controller.tasks.isEmpty)
    }
}
