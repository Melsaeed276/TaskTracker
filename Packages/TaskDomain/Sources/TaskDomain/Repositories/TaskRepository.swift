import Foundation

public protocol TaskRepository: Sendable {
    func task(id: UUID) throws -> Task?
    func allTasks() throws -> [Task]
    func poolTasks() throws -> [Task]
    func tasks(scheduledFor day: DayKey) throws -> [Task]
    func completedTasks() throws -> [Task]

    func upsert(_ task: Task) throws
    func deleteTask(id: UUID) throws
}

