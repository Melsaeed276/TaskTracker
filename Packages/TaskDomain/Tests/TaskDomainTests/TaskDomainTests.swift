import Foundation
import Testing
@testable import TaskDomain

@Suite("TaskDomain")
struct TaskDomainTests {
    @Test("Title validation: trimmed title must be non-empty")
    func titleValidation() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(throws: TaskValidationError.emptyTitle) {
            _ = try TaskService.create(title: "   \n\t", now: now)
        }

        let t = try? TaskService.create(title: "  Hello  ", notes: nil, now: now)
        #expect(t?.title == "Hello")
    }

    @Test("Completion is derived and idempotent; completing does not clear scheduledDay")
    func completionIdempotence() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!

        let created = try TaskService.create(title: "A", now: now)
        let scheduled = TaskService.scheduleForToday(created, now: now, calendar: cal)
        #expect(scheduled.scheduledDay == DayKey(rawValue: "2023-11-14"))

        let first = try TaskService.complete(scheduled, now: now.addingTimeInterval(10))
        #expect(first.isCompleted)
        #expect(first.scheduledDay == scheduled.scheduledDay)

        let second = try TaskService.complete(first, now: now.addingTimeInterval(20))
        #expect(second.completedAt == first.completedAt)
        #expect(second.isCompleted)
        #expect(second.scheduledDay == first.scheduledDay)
    }

    @Test("Pool vs Today query semantics")
    func poolAndTodaySemantics() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let t0 = try TaskService.create(title: "A", now: now)
        #expect(t0.isInPool)

        let day = DayKey(rawValue: "2026-08-09")
        let t1 = TaskService.schedule(t0, for: day, now: now)
        #expect(!t1.isInPool)
        #expect(t1.status == .scheduled(day))

        let t2 = TaskService.unschedule(t1, now: now)
        #expect(t2.isInPool)

        let t3 = try TaskService.complete(t2, now: now)
        #expect(!t3.isInPool)
        #expect(t3.status == .completed)
    }

    @Test("DayKey is assignment-calendar truth across timezone travel and DST boundaries")
    func dayKeyCalendarFact() throws {
        let instant = Date(timeIntervalSince1970: 1_754_704_800) // 2025-08-11T01:00:00Z
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        let tokyoDay = DayKey.from(date: instant, calendar: tokyo)
        let laDay = DayKey.from(date: instant, calendar: la)
        #expect(tokyoDay.rawValue == "2025-08-09")
        #expect(laDay.rawValue == "2025-08-08")
        #expect(tokyoDay != laDay)

        // A task scheduled while in Tokyo keeps that stored day key after a timezone change.
        let created = try TaskService.create(title: "Timezone-stable", now: instant)
        let scheduledInTokyo = TaskService.scheduleForToday(created, now: instant, calendar: tokyo)
        #expect(scheduledInTokyo.scheduledDay == tokyoDay)
        #expect(scheduledInTokyo.scheduledDay != laDay)

        // DST spring-forward in New York: local "day" stays stable across the missing hour.
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        let beforeJump = ny.date(from: DateComponents(
            year: 2026, month: 3, day: 8, hour: 1, minute: 59
        ))!
        let afterJump = ny.date(from: DateComponents(
            year: 2026, month: 3, day: 8, hour: 3, minute: 1
        ))!
        #expect(DayKey.from(date: beforeJump, calendar: ny).rawValue == "2026-03-08")
        #expect(DayKey.from(date: afterJump, calendar: ny).rawValue == "2026-03-08")
    }
}
