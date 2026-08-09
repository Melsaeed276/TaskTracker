import Foundation
import Testing
import TimerDomain
@testable import AppData

/// Milestone 4 convergence proof: two devices, each holding its own local `ModelContainer`, write
/// independently, and their event logs are merged the way CloudKit mirroring eventually merges two
/// private-database replicas — by unioning rows, never by rewriting them. These tests exercise that
/// union through the real repository/container path so the proof isn't purely at the `TimerDomain`
/// level (already covered in Packages/TimerDomain/Tests) but through the persistence seam Milestone 4
/// is meant to validate. Real-hardware CloudKit verification is still required later (see
/// memory.md) — this is the reference oracle that hardware run must agree with.
@Suite("AppData Convergence Proof (Milestone 4)")
struct ConvergenceProofTests {
    private static let base = Date(timeIntervalSince1970: 1_700_000_000)

    /// Two devices offline-start independent sessions. Merging their logs in either order must
    /// produce the identical winner: the later `startedAt` wins (wall-clock, then deviceID —
    /// SessionArbitration's tie-break), and the earlier session is permanently superseded.
    @Test("Two offline starts converge to the same winner regardless of merge order")
    func twoOfflineStartsConverge() async throws {
        let deviceA = UUID()
        let deviceB = UUID()
        let sessionA = UUID()
        let sessionB = UUID()

        let startA = TimerEvent(
            id: UUID(),
            sessionID: sessionA,
            kind: TimerEventKind.started.rawValue,
            occurredAt: Self.base,
            deviceID: deviceA,
            lamport: 1,
            schemaVersion: 1,
            duration: 60
        )

        // Device B starts 10s later, while still offline from A.
        let startB = TimerEvent(
            id: UUID(),
            sessionID: sessionB,
            kind: TimerEventKind.started.rawValue,
            occurredAt: Self.base.addingTimeInterval(10),
            deviceID: deviceB,
            lamport: 1,
            schemaVersion: 1,
            duration: 60
        )

        let eventsFromA = try await writeAndReadBack([startA])
        let eventsFromB = try await writeAndReadBack([startB])

        let mergedAThenB = eventsFromA + eventsFromB
        let mergedBThenA = eventsFromB + eventsFromA

        let evaluationTime = Self.base.addingTimeInterval(15)
        let resultAThenB = TimerEngine.evaluateActiveTimer(events: mergedAThenB, at: evaluationTime)
        let resultBThenA = TimerEngine.evaluateActiveTimer(events: mergedBThenA, at: evaluationTime)

        #expect(resultAThenB == resultBThenA)

        guard case .active(let winner, _) = resultAThenB else {
            Issue.record("Expected an active winner, got \(resultAThenB)")
            return
        }
        // B started later, so B wins the wall-clock arbitration.
        #expect(winner.id == sessionB)
    }

    /// Once superseded, a session cannot be revived by any later event on it — including a stop
    /// issued on what is now (incorrectly, from a stale client's point of view) believed to be the
    /// active session. Stopping the *winner* must yield global `.idle`, never resurrect the loser.
    @Test("Supersession survives the round trip through two containers and a stop on the winner")
    func supersessionPermanentAcrossContainers() async throws {
        let deviceA = UUID()
        let deviceB = UUID()
        let sessionA = UUID()
        let sessionB = UUID()

        let startA = TimerEvent(
            id: UUID(), sessionID: sessionA, kind: TimerEventKind.started.rawValue,
            occurredAt: Self.base, deviceID: deviceA, lamport: 1, schemaVersion: 1, duration: 60
        )
        let startB = TimerEvent(
            id: UUID(), sessionID: sessionB, kind: TimerEventKind.started.rawValue,
            occurredAt: Self.base.addingTimeInterval(10), deviceID: deviceB, lamport: 1,
            schemaVersion: 1, duration: 60
        )
        let stopB = TimerEvent(
            id: UUID(), sessionID: sessionB, kind: TimerEventKind.stopped.rawValue,
            occurredAt: Self.base.addingTimeInterval(12), deviceID: deviceB, lamport: 2,
            schemaVersion: 1
        )

        // Device A only ever knows about its own start. Device B knows about its own start-then-stop.
        let eventsFromA = try await writeAndReadBack([startA])
        let eventsFromB = try await writeAndReadBack([startB, stopB])

        let merged = eventsFromA + eventsFromB
        let result = TimerEngine.evaluateActiveTimer(events: merged, at: Self.base.addingTimeInterval(20))

        // B (the winner) was stopped. A never revives even though it was never explicitly stopped.
        #expect(result == .idle)
    }

    /// The same logical event (identical `id`), appended twice to simulate a CloudKit resync or
    /// retry, must not change the projection. The fold dedupes by event id.
    @Test("Duplicate delivery of the same event id does not change the projection")
    func duplicateDeliveryIsIdempotent() async throws {
        let device = UUID()
        let session = UUID()
        let start = TimerEvent(
            id: UUID(), sessionID: session, kind: TimerEventKind.started.rawValue,
            occurredAt: Self.base, deviceID: device, lamport: 1, schemaVersion: 1, duration: 60
        )

        let container = try await MainActor.run { try AppDataModelContainer.makeLocalInMemory() }
        let repo = SwiftDataTimerEventRepository(modelContainer: container)

        try await repo.append(start)
        try await repo.append(start) // simulated resync delivering the same event id again

        let stored = try await repo.loadAllEvents()
        // The store itself may hold two rows (no unique constraint under CloudKit, per AGENTS.md —
        // dedupe happens in the fold, not the store), but projecting them must be idempotent.
        let evaluationTime = Self.base.addingTimeInterval(5)
        let resultWithDuplicate = TimerEngine.evaluateActiveTimer(events: stored, at: evaluationTime)
        let resultWithoutDuplicate = TimerEngine.evaluateActiveTimer(events: [start], at: evaluationTime)

        #expect(resultWithDuplicate == resultWithoutDuplicate)
    }

    private func writeAndReadBack(_ events: [TimerEvent]) async throws -> [TimerEvent] {
        let container = try await MainActor.run { try AppDataModelContainer.makeLocalInMemory() }
        let repo = SwiftDataTimerEventRepository(modelContainer: container)
        for event in events {
            try await repo.append(event)
        }
        return try await repo.loadAllEvents()
    }
}
