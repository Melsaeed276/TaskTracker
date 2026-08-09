import SwiftData

public enum AppDataModelContainer: Sendable {
    @MainActor
    public static func makeLocalInMemory() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: TaskRecord.self,
            TimerEventRecord.self,
            configurations: config
        )
    }
}

