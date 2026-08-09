import Foundation
@testable import TimerDomain

struct TestRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

enum TestLog {
    static let base = Date(timeIntervalSince1970: 1_700_000_000)

    static func simpleRunningSession(duration: TimeInterval = 60) -> (events: [TimerEvent], supersededAt: Date?) {
        let sessionID = uuid(1)
        let deviceID = uuid(2)
        let started = TimerEvent(
            id: uuid(3),
            sessionID: sessionID,
            kind: TimerEventKind.started.rawValue,
            occurredAt: base,
            deviceID: deviceID,
            lamport: 1,
            schemaVersion: 1,
            duration: duration,
            relatedTaskID: uuid(4)
        )

        let paused = TimerEvent(
            id: uuid(5),
            sessionID: sessionID,
            kind: TimerEventKind.paused.rawValue,
            occurredAt: base.addingTimeInterval(10),
            deviceID: deviceID,
            lamport: 2,
            schemaVersion: 1
        )

        let resumed = TimerEvent(
            id: uuid(6),
            sessionID: sessionID,
            kind: TimerEventKind.resumed.rawValue,
            occurredAt: base.addingTimeInterval(20),
            deviceID: deviceID,
            lamport: 3,
            schemaVersion: 1
        )

        return ([started, paused, resumed], nil)
    }

    static func twoSessionsWinnerStopped() -> [TimerEvent] {
        let deviceA = uuid(10)
        let deviceB = uuid(11)

        let sessionA = uuid(12)
        let startA = TimerEvent(
            id: uuid(13),
            sessionID: sessionA,
            kind: TimerEventKind.started.rawValue,
            occurredAt: base,
            deviceID: deviceA,
            lamport: 1,
            schemaVersion: 1,
            duration: 60,
            relatedTaskID: nil
        )

        let sessionB = uuid(14)
        let startB = TimerEvent(
            id: uuid(15),
            sessionID: sessionB,
            kind: TimerEventKind.started.rawValue,
            occurredAt: base.addingTimeInterval(10),
            deviceID: deviceB,
            lamport: 1,
            schemaVersion: 1,
            duration: 60,
            relatedTaskID: nil
        )

        let stopB = TimerEvent(
            id: uuid(16),
            sessionID: sessionB,
            kind: TimerEventKind.stopped.rawValue,
            occurredAt: base.addingTimeInterval(12),
            deviceID: deviceB,
            lamport: 2,
            schemaVersion: 1
        )

        // Note: no stop for A. After stopping B, global state must be idle; A never revives.
        return [startA, startB, stopB]
    }

    static func sessionASupersededByStartB() -> (eventsA: [TimerEvent], startB: Date) {
        let deviceA = uuid(20)
        let sessionA = uuid(21)
        let startA = TimerEvent(
            id: uuid(22),
            sessionID: sessionA,
            kind: TimerEventKind.started.rawValue,
            occurredAt: base,
            deviceID: deviceA,
            lamport: 1,
            schemaVersion: 1,
            duration: 60
        )

        // A runs for 10 seconds and is then superseded by session B's start.
        let startB = base.addingTimeInterval(10)
        return ([startA], startB)
    }

    static func sessionWithUnknownKind() -> (events: [TimerEvent], unknownKind: String) {
        let sessionID = uuid(30)
        let deviceID = uuid(31)
        let unknown = "future.noop"

        let started = TimerEvent(
            id: uuid(32),
            sessionID: sessionID,
            kind: TimerEventKind.started.rawValue,
            occurredAt: base,
            deviceID: deviceID,
            lamport: 1,
            schemaVersion: 1,
            duration: 60
        )

        let unknownEvent = TimerEvent(
            id: uuid(33),
            sessionID: sessionID,
            kind: unknown,
            occurredAt: base.addingTimeInterval(5),
            deviceID: deviceID,
            lamport: 2,
            schemaVersion: 1
        )

        return ([started, unknownEvent], unknown)
    }

    static func randomLog(seed: UInt64) -> [TimerEvent] {
        var rng = TestRNG(seed: seed)

        let deviceA = randomUUID(using: &rng)
        let deviceB = randomUUID(using: &rng)

        let sessionCount = Int(rng.next() % 3) + 1 // 1...3
        var sessions: [(id: UUID, device: UUID, startedAt: Date, duration: TimeInterval)] = []
        sessions.reserveCapacity(sessionCount)

        var cursor = base
        for _ in 0..<sessionCount {
            cursor = cursor.addingTimeInterval(TimeInterval(Int(rng.next() % 20)))
            let sid = randomUUID(using: &rng)
            let device = (rng.next() % 2 == 0) ? deviceA : deviceB
            let duration = TimeInterval(Int(rng.next() % 120) + 1)
            sessions.append((sid, device, cursor, duration))
        }

        var events: [TimerEvent] = []
        var eventCounter: UInt64 = 1

        for session in sessions {
            var lamport = 1
            var t = session.startedAt

            events.append(
                TimerEvent(
                    id: randomUUID(tag: eventCounter, using: &rng),
                    sessionID: session.id,
                    kind: TimerEventKind.started.rawValue,
                    occurredAt: t,
                    deviceID: session.device,
                    lamport: lamport,
                    schemaVersion: 1,
                    duration: session.duration
                )
            )
            eventCounter += 1

            let steps = Int(rng.next() % 6) // 0...5
            for _ in 0..<steps {
                t = t.addingTimeInterval(TimeInterval(Int(rng.next() % 10) + 1))
                lamport += 1
                eventCounter += 1

                let roll = Int(rng.next() % 10)
                let kind: String
                switch roll {
                case 0: kind = TimerEventKind.paused.rawValue
                case 1: kind = TimerEventKind.resumed.rawValue
                case 2: kind = TimerEventKind.stopped.rawValue
                case 3: kind = TimerEventKind.reset.rawValue
                case 4: kind = "future.noop" // unknown in v1
                default:
                    // Invalid/no-op transitions are expected; projection must remain total.
                    kind = (rng.next() % 2 == 0) ? TimerEventKind.paused.rawValue : TimerEventKind.resumed.rawValue
                }

                events.append(
                    TimerEvent(
                        id: randomUUID(tag: eventCounter, using: &rng),
                        sessionID: session.id,
                        kind: kind,
                        occurredAt: t,
                        deviceID: session.device,
                        lamport: lamport,
                        schemaVersion: 1
                    )
                )

                if kind == TimerEventKind.stopped.rawValue || kind == TimerEventKind.reset.rawValue {
                    break
                }
            }
        }

        return events
    }

    private static func uuid(_ n: UInt8) -> UUID {
        // Deterministic UUIDs for stable tests.
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[15] = n
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5],
            bytes[6], bytes[7],
            bytes[8], bytes[9],
            bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

private func randomUUID(using rng: inout TestRNG) -> UUID {
    randomUUID(tag: rng.next(), using: &rng)
}

private func randomUUID(tag: UInt64, using rng: inout TestRNG) -> UUID {
    var bytes = [UInt8](repeating: 0, count: 16)
    for i in 0..<16 {
        bytes[i] = UInt8(truncatingIfNeeded: rng.next())
    }
    // Mix in tag for stability.
    bytes[0] ^= UInt8(truncatingIfNeeded: tag)
    bytes[15] ^= UInt8(truncatingIfNeeded: tag >> 8)
    return UUID(uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3],
        bytes[4], bytes[5],
        bytes[6], bytes[7],
        bytes[8], bytes[9],
        bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
    ))
}


