import SwiftData
import TimerDomain

@ModelActor
public actor SwiftDataTimerEventRepository {}

extension SwiftDataTimerEventRepository: TimerEventRepository {
    public func loadAllEvents() async throws -> [TimerEvent] {
        let fetch = FetchDescriptor<TimerEventRecord>()
        return try modelContext.fetch(fetch).map(TimerEventMapping.toDomain)
    }

    public func append(_ event: TimerEvent) async throws {
        // No unique constraint under CloudKit; even locally we accept duplicates and rely on
        // domain projection to dedupe by id.
        modelContext.insert(TimerEventMapping.makeRecord(from: event))
        try modelContext.save()
    }
}

