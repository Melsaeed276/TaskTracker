import Foundation

public protocol TaskRepository: Sendable {
    func task(id: UUID) async throws -> Task?
    func allTasks() async throws -> [Task]
    func poolTasks() async throws -> [Task]
    func tasks(scheduledFor day: DayKey) async throws -> [Task]
    func completedTasks() async throws -> [Task]

    func upsert(_ task: Task) async throws
    func deleteTask(id: UUID) async throws
}

