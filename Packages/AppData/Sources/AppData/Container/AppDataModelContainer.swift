import SwiftData

public enum AppDataModelContainer: Sendable {
    /// The private CloudKit container mirrored by `makeSynced()`. Matches the entitlement
    /// declared on each app target once signing is configured (see docs/ICLOUD_SYNC.md).
    public static let cloudKitContainerIdentifier = "iCloud.com.diwan.TaskTracker"

    @MainActor
    public static func makeLocalInMemory() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: TaskRecord.self,
            TimerEventRecord.self,
            configurations: config
        )
    }

    /// The production container: on-disk storage mirrored to the private CloudKit database.
    /// Both `TaskRecord` and `TimerEventRecord` have no relationships, no unique attributes, and
    /// every stored property is optional or defaulted — the CloudKit mirroring contract SwiftData
    /// requires (see AGENTS.md, docs/ICLOUD_SYNC.md). Requires the app target's entitlement for
    /// `cloudKitContainerIdentifier` to be configured before this will actually sync; until then it
    /// still works as a local on-disk store (SwiftData reports sync errors, not construction
    /// failures, when the entitlement is missing).
    @MainActor
    public static func makeSynced() throws -> ModelContainer {
        let config = ModelConfiguration(
            cloudKitDatabase: .private(cloudKitContainerIdentifier)
        )
        return try ModelContainer(
            for: TaskRecord.self,
            TimerEventRecord.self,
            configurations: config
        )
    }
}

