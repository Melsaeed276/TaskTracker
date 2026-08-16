import Foundation
import os
import SwiftData
import TimerDomain

@ModelActor
public actor SwiftDataTimerEventRepository {
    private static let spikeR1Logger = Logger(
        subsystem: "com.diwan.TaskTracker",
        category: "SpikeR1"
    )
}

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
        let writeCompletedAt = Date()
        let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        Self.spikeR1Logger.info(
            "spike_r1_append eventID=\(event.id.uuidString, privacy: .public) kind=\(event.kind, privacy: .public) deviceID=\(event.deviceID.uuidString, privacy: .public) occurredAt=\(event.occurredAt.formatted(iso), privacy: .public) writeCompletedAt=\(writeCompletedAt.formatted(iso), privacy: .public)"
        )
    }
}

