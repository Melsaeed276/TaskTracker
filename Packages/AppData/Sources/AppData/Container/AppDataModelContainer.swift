import SwiftData

public enum AppDataModelContainer: Sendable {
    public static func makeLocalInMemory() throws -> ModelContainer {
        let schema = Schema([
            TaskRecord.self,
            TimerEventRecord.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }
}

