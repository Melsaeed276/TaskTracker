import SwiftData
import TimerDomain

public protocol AppDataTimerEventRepository: TimerEventRepository {}

public actor SwiftDataTimerEventRepository: Sendable {
    private let actor: AppDataModelActor

    public init(modelContainer: ModelContainer) {
        self.actor = AppDataModelActor(modelContainer: modelContainer)
    }
}

extension SwiftDataTimerEventRepository: AppDataTimerEventRepository {
    public func loadAllEvents() throws -> [TimerEvent] {
        try actor.modelContext.perform {
            let fetch = FetchDescriptor<TimerEventRecord>()
            return try actor.modelContext.fetch(fetch).map(TimerEventMapping.toDomain)
        }
    }

    public func append(_ event: TimerEvent) throws {
        try actor.modelContext.perform {
            // No unique constraint under CloudKit; even locally we accept duplicates and rely on
            // domain projection to dedupe by id.
            actor.modelContext.insert(TimerEventMapping.makeRecord(from: event))
            try actor.modelContext.save()
        }
    }
}

