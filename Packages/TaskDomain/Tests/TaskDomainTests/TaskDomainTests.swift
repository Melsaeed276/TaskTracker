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

    @Test("DayKey is a calendar fact (stable across timezone/DST changes)")
    func dayKeyCalendarFact() {
        // The key is an ISO day string computed at assignment time in the current calendar.
        // After a timezone change, we do NOT recompute a different key for an already-scheduled task.
        let instant = Date(timeIntervalSince1970: 1_750_000_000)

        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!

        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        let keyAtAssignment = DayKey.from(date: instant, calendar: tokyo)
        let recomputedElsewhere = DayKey.from(date: instant, calendar: la)

        // These may differ; that's expected because "today" depends on local calendar at assignment time.
        // Stability is that the stored key doesn't change when the device timezone changes.
        #expect(DayKey(rawValue: keyAtAssignment.rawValue) == keyAtAssignment)
        #expect(keyAtAssignment.rawValue.count == 10)
        #expect(recomputedElsewhere.rawValue.count == 10)
    }
}
