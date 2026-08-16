import Foundation
import Testing
@testable import TimerDomain

@Suite("TimerDomain")
struct TimerDomainTests {
    @Test("Projection is timeless; only evaluation depends on the clock")
    func projectionTimelessness() {
        let (events, supersededAt) = TestLog.simpleRunningSession(duration: 60)
        let projectionA = TimerProjection.project(events: events, supersededAt: supersededAt)
        let projectionB = TimerProjection.project(events: events, supersededAt: supersededAt)
        #expect(projectionA == projectionB)

        let early = TestLog.base.addingTimeInterval(30)
        let late = TestLog.base.addingTimeInterval(120)
        let stateEarly = TimerCalculator.evaluateSession(projectionA, at: early)
        let stateLate = TimerCalculator.evaluateSession(projectionA, at: late)
        #expect(stateEarly != stateLate)
    }

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

    @Test("Bounded winner-query evaluation matches full-log reference evaluation")
    func boundedQueryEquivalenceAgainstFullLogReference() {
        for seed in 0..<100 {
            let events = TestLog.randomLog(seed: UInt64(seed) &+ 4000)
            let at = TestLog.base.addingTimeInterval(TimeInterval((seed % 180) + 1))
            let bounded = TimerEngine.evaluateActiveTimer(events: events, at: at)
            let fullLog = referenceEvaluateActiveTimer(events: events, at: at)
            #expect(bounded == fullLog)
        }
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

    @Test("Elapsed and remaining are correct across pause/resume cycles")
    func elapsedRemainingAcrossPauseResumeCycles() {
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000111")!
        let deviceID = UUID(uuidString: "00000000-0000-0000-0000-000000000112")!
        let events: [TimerEvent] = [
            TimerEvent(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000113")!,
                sessionID: sessionID,
                kind: TimerEventKind.started.rawValue,
                occurredAt: TestLog.base,
                deviceID: deviceID,
                lamport: 1,
                schemaVersion: 1,
                duration: 100
            ),
            TimerEvent(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000114")!,
                sessionID: sessionID,
                kind: TimerEventKind.paused.rawValue,
                occurredAt: TestLog.base.addingTimeInterval(10),
                deviceID: deviceID,
                lamport: 2,
                schemaVersion: 1
            ),
            TimerEvent(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000115")!,
                sessionID: sessionID,
                kind: TimerEventKind.resumed.rawValue,
                occurredAt: TestLog.base.addingTimeInterval(30),
                deviceID: deviceID,
                lamport: 3,
                schemaVersion: 1
            ),
            TimerEvent(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000116")!,
                sessionID: sessionID,
                kind: TimerEventKind.paused.rawValue,
                occurredAt: TestLog.base.addingTimeInterval(50),
                deviceID: deviceID,
                lamport: 4,
                schemaVersion: 1
            ),
            TimerEvent(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000117")!,
                sessionID: sessionID,
                kind: TimerEventKind.resumed.rawValue,
                occurredAt: TestLog.base.addingTimeInterval(70),
                deviceID: deviceID,
                lamport: 5,
                schemaVersion: 1
            )
        ]

        let projection = TimerProjection.project(events: events, supersededAt: nil)
        let pausedAt60 = TestLog.base.addingTimeInterval(60)
        #expect(TimerCalculator.elapsed(projection, at: pausedAt60) == 30)
        #expect(TimerCalculator.remaining(projection, at: pausedAt60) == 70)

        let runningAt80 = TestLog.base.addingTimeInterval(80)
        #expect(TimerCalculator.elapsed(projection, at: runningAt80) == 40)
        #expect(TimerCalculator.remaining(projection, at: runningAt80) == 60)
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

    @Test("Simultaneous starts arbitrate by device identifier tie-break")
    func simultaneousStartsArbitrateByDeviceID() {
        let tieTime = TestLog.base
        let sessionA = UUID(uuidString: "00000000-0000-0000-0000-000000000121")!
        let sessionB = UUID(uuidString: "00000000-0000-0000-0000-000000000122")!
        let lowDevice = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let highDevice = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

        let events: [TimerEvent] = [
            TimerEvent(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
                sessionID: sessionA,
                kind: TimerEventKind.started.rawValue,
                occurredAt: tieTime,
                deviceID: lowDevice,
                lamport: 1,
                schemaVersion: 1,
                duration: 60
            ),
            TimerEvent(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000124")!,
                sessionID: sessionB,
                kind: TimerEventKind.started.rawValue,
                occurredAt: tieTime,
                deviceID: highDevice,
                lamport: 1,
                schemaVersion: 1,
                duration: 60
            )
        ]

        let result = TimerEngine.evaluateActiveTimer(
            events: events,
            at: tieTime.addingTimeInterval(1)
        )
        guard case .active(let session, _) = result else {
            Issue.record("Expected a winner, got \(result)")
            return
        }
        #expect(session.id == sessionB)
    }

    @Test("Reset discards accumulated elapsed time and evaluates to idle")
    func resetDiscardsElapsedTime() {
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-0000000000DD")!
        let deviceID = UUID(uuidString: "00000000-0000-0000-0000-0000000000EE")!
        let started = TimerEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000FF")!,
            sessionID: sessionID,
            kind: TimerEventKind.started.rawValue,
            occurredAt: TestLog.base,
            deviceID: deviceID,
            lamport: 1,
            schemaVersion: 1,
            duration: 60,
            relatedTaskID: nil
        )
        let resetAt = TestLog.base.addingTimeInterval(15)
        let reset = TimerEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000100")!,
            sessionID: sessionID,
            kind: TimerEventKind.reset.rawValue,
            occurredAt: resetAt,
            deviceID: deviceID,
            lamport: 2,
            schemaVersion: 1
        )
        let events = [started, reset]

        let projection = TimerProjection.project(events: events, supersededAt: nil)
        #expect(projection.session?.accumulatedActive == 0)
        #expect(projection.session?.terminalEvent == .reset(at: resetAt))
        #expect(projection.runningSince == nil)

        let sessionState = TimerCalculator.evaluateSession(projection, at: resetAt.addingTimeInterval(1))
        #expect(sessionState.isCompleted == false)

        let globalState = TimerEngine.evaluateActiveTimer(events: events, at: resetAt.addingTimeInterval(1))
        #expect(globalState == .idle)
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

    @Test("TimerTransition validity matrix is explicit for valid and invalid transitions")
    func transitionValidityMatrix() {
        let valid: [(TimerTransition.SessionState?, TimerEventKind, TimerTransition.SessionState)] = [
            (nil, .started, .running),
            (.running, .paused, .paused),
            (.paused, .resumed, .running),
            (.running, .stopped, .stopped),
            (.paused, .stopped, .stopped),
            (.running, .reset, .reset),
            (.paused, .reset, .reset),
            (.stopped, .reset, .reset)
        ]

        for (state, event, expected) in valid {
            #expect(TimerTransition.nextState(from: state, applying: event) == expected)
        }

        let allStates: [TimerTransition.SessionState?] = [nil, .running, .paused, .stopped, .reset]
        let allEvents: [TimerEventKind] = [.started, .paused, .resumed, .stopped, .reset]
        let validKeys = Set(valid.map { transitionKey(state: $0.0, event: $0.1) })

        for state in allStates {
            for event in allEvents {
                let key = transitionKey(state: state, event: event)
                if validKeys.contains(key) { continue }
                #expect(TimerTransition.nextState(from: state, applying: event) == nil)
            }
        }
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

private func referenceEvaluateActiveTimer(
    events: [TimerEvent],
    at: Date
) -> ActiveTimerState {
    let deduped = dedupeEventsForReference(events)
    let starts = deduped.filter { $0.kind == TimerEventKind.started.rawValue }
    guard !starts.isEmpty else { return .idle }

    let winnerStart = starts.max(by: { compareStarts($0, $1) == .orderedAscending })!
    let sortedStarts = starts.sorted(by: { compareStarts($0, $1) == .orderedAscending })
    let winnerIndex = sortedStarts.firstIndex(where: { $0.id == winnerStart.id })!
    let nextIndex = sortedStarts.index(after: winnerIndex)
    let supersededAt = nextIndex < sortedStarts.endIndex ? sortedStarts[nextIndex].occurredAt : nil

    let winnerEvents = deduped.filter { $0.sessionID == winnerStart.sessionID }
    let projection = TimerProjection.project(events: winnerEvents, supersededAt: supersededAt)
    return TimerCalculator.evaluateActive(projection, at: at)
}

private func dedupeEventsForReference(_ events: [TimerEvent]) -> [TimerEvent] {
    let sorted = events.sorted(by: referenceCanonicalSort)
    var seen = Set<UUID>()
    var out: [TimerEvent] = []
    out.reserveCapacity(sorted.count)
    for event in sorted where !seen.contains(event.id) {
        seen.insert(event.id)
        out.append(event)
    }
    return out
}

private func referenceCanonicalSort(_ a: TimerEvent, _ b: TimerEvent) -> Bool {
    if a.id != b.id { return a.id.uuidString < b.id.uuidString }
    if a.sessionID != b.sessionID { return a.sessionID.uuidString < b.sessionID.uuidString }
    if a.occurredAt != b.occurredAt { return a.occurredAt < b.occurredAt }
    if a.lamport != b.lamport { return a.lamport < b.lamport }
    if a.deviceID != b.deviceID { return a.deviceID.uuidString < b.deviceID.uuidString }
    return a.kind < b.kind
}

private func compareStarts(_ a: TimerEvent, _ b: TimerEvent) -> ComparisonResult {
    if a.occurredAt != b.occurredAt { return a.occurredAt < b.occurredAt ? .orderedAscending : .orderedDescending }
    if a.deviceID != b.deviceID { return a.deviceID.uuidString < b.deviceID.uuidString ? .orderedAscending : .orderedDescending }
    if a.id != b.id { return a.id.uuidString < b.id.uuidString ? .orderedAscending : .orderedDescending }
    return .orderedSame
}

private func transitionKey(state: TimerTransition.SessionState?, event: TimerEventKind) -> String {
    "\(String(describing: state))|\(event.rawValue)"
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

