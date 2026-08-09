import Foundation
import Testing
@testable import TimerDomain

@Suite("TimerDomain")
struct TimerDomainTests {
    @Test("TimerTransition rejects stale commands")
    func transitionRejectsStaleCommands() {
        #expect(TimerTransition.nextState(from: .stopped, applying: .resumed) == nil)
        #expect(TimerTransition.nextState(from: .paused, applying: .paused) == nil)
        #expect(TimerTransition.nextState(from: nil, applying: .resumed) == nil)
    }

    @Test("Projection is idempotent over duplicated events")
    func projectionIdempotentOverDuplicates() {
        let (events, supersededAt) = TestLog.simpleRunningSession()
        var rng = TestRNG(seed: 1)
        let dupes = Array(events.shuffled(using: &rng).prefix(2))
        let withDuplicates = events + dupes

        let a = TimerProjection.project(events: events, supersededAt: supersededAt)
        let b = TimerProjection.project(events: withDuplicates, supersededAt: supersededAt)
        #expect(a == b)
    }

    @Test("Projection is order-independent under shuffling")
    func projectionOrderIndependent() {
        let (events, supersededAt) = TestLog.simpleRunningSession()
        var rng = TestRNG(seed: 2)
        let shuffled = events.shuffled(using: &rng)

        let a = TimerProjection.project(events: events, supersededAt: supersededAt)
        let b = TimerProjection.project(events: shuffled, supersededAt: supersededAt)
        #expect(a == b)
    }

    @Test("Expiry is derived by evaluate(at:)")
    func expiryIsDerived() {
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
        let deviceID = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!
        let started = TimerEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000CC")!,
            sessionID: sessionID,
            kind: TimerEventKind.started.rawValue,
            occurredAt: TestLog.base,
            deviceID: deviceID,
            lamport: 1,
            schemaVersion: 1,
            duration: 10,
            relatedTaskID: nil
        )
        let events = [started]
        let at9 = TestLog.base.addingTimeInterval(9)
        let at10 = TestLog.base.addingTimeInterval(10)

        let projection = TimerProjection.project(events: events, supersededAt: nil)
        let state9 = TimerCalculator.evaluateSession(projection, at: at9)
        let state10 = TimerCalculator.evaluateSession(projection, at: at10)

        #expect(state9.isCompleted == false)
        #expect(state10.isCompleted == true)
        #expect(state10.completionReason == CompletionReason.expired)
    }

    @Test("Stopping the winning session does not resurrect a superseded session")
    func arbitrationPermanence() {
        let events = TestLog.twoSessionsWinnerStopped()
        let at = TestLog.base.addingTimeInterval(100)
        let active = TimerEngine.evaluateActiveTimer(events: events, at: at)
        #expect(active == .idle)
    }

    @Test("Supersession cutoff truncates elapsed for history")
    func supersessionCutoff() {
        let (eventsA, startB) = TestLog.sessionASupersededByStartB()
        let projectionA = TimerProjection.project(events: eventsA, supersededAt: startB)
        #expect(projectionA.session?.accumulatedActive == 10)
        #expect(projectionA.runningSince == nil)
    }

    @Test("Unknown kinds quarantine a session and quarantine lifts when kind becomes known")
    func quarantineAndLifting() {
        let (events, _) = TestLog.sessionWithUnknownKind()

        let v1 = TimerSchema.v1
        let p1 = TimerProjection.project(events: events, supersededAt: nil, schema: v1)
        #expect(p1.session?.quarantine.isQuarantined == true)

        var v2 = TimerSchema.v1
        v2.knownKinds.insert("future.noop")
        let p2 = TimerProjection.project(events: events, supersededAt: nil, schema: v2)
        #expect(p2.session?.quarantine.isQuarantined == false)
    }

    @Test("Quarantined sessions allow stop/start but withhold pause/resume/reset")
    func quarantineAuthoringPolicy() {
        let quarantined = true
        #expect(TimerAuthoringPolicy.isAuthorable(.started, quarantined: quarantined))
        #expect(TimerAuthoringPolicy.isAuthorable(.stopped, quarantined: quarantined))
        #expect(!TimerAuthoringPolicy.isAuthorable(.paused, quarantined: quarantined))
        #expect(!TimerAuthoringPolicy.isAuthorable(.resumed, quarantined: quarantined))
        #expect(!TimerAuthoringPolicy.isAuthorable(.reset, quarantined: quarantined))
    }

    @Test("Randomized invariants: idempotent + order-independent + stable winner")
    func randomizedInvariants() {
        for seed in 0..<50 {
            let log = TestLog.randomLog(seed: UInt64(seed))

            let index = SessionArbitration.startIndex(from: log)
            let winner = SessionArbitration.winningSession(from: index)?.sessionID

            var rng = TestRNG(seed: UInt64(seed) &+ 999)
            let shuffledLog = log.shuffled(using: &rng)
            let shuffledWinner = SessionArbitration.winningSession(from: SessionArbitration.startIndex(from: shuffledLog))?.sessionID
            #expect(winner == shuffledWinner)

            for start in index {
                let cutoff = SessionArbitration.supersededAt(for: start.sessionID, in: index)
                let events = log.filter { $0.sessionID == start.sessionID }

                let p1 = TimerProjection.project(events: events, supersededAt: cutoff)

                var rng2 = TestRNG(seed: UInt64(seed) &+ 12345)
                var perm = events.shuffled(using: &rng2)
                if let first = perm.first { perm.append(first) } // duplicate by id
                let p2 = TimerProjection.project(events: perm, supersededAt: cutoff)

                #expect(p1 == p2)
            }
        }
    }
}

private extension ActiveTimerState {
    var isCompleted: Bool {
        if case .completed = self { return true }
        return false
    }

    var completionReason: CompletionReason? {
        guard case .completed(_, let reason) = self else { return nil }
        return reason
    }
}

