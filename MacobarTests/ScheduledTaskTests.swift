import Foundation
import Testing

/// Verifies when scheduled tasks run next and that the store keeps them.
struct ScheduledTaskTests {
    /// A Gregorian calendar in GMT, so results don't depend on the machine's time zone.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    /// The moment on `day` October 2026 (the 28th is a Wednesday) at `hour`:`minute`:`second`.
    private func october(_ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) throws -> Date {
        let components = DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second)
        return try #require(calendar.date(from: components))
    }

    /// The moment on `day` November 2026 at `hour`:00.
    private func november(_ day: Int, _ hour: Int) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour)))
    }

    @Test("A one-off task has no next run")
    func neverRepeats() throws {
        #expect(RepeatRule.never.nextRun(after: try october(28, 9, 0, 5), from: try october(28, 9), in: calendar) == nil)
    }

    @Test("An hourly task runs next at the same minute of the following hour")
    func hourly() throws {
        let next = RepeatRule.hourly.nextRun(after: try october(28, 9, 30, 5), from: try october(28, 9, 30), in: calendar)
        #expect(next == (try october(28, 10, 30)))
    }

    @Test("A daily task runs next at the same time tomorrow")
    func daily() throws {
        let next = RepeatRule.daily.nextRun(after: try october(28, 9, 0, 5), from: try october(28, 9), in: calendar)
        #expect(next == (try october(29, 9)))
    }

    @Test("A weekday task due on Friday runs next on Monday")
    func weekdaysSkipWeekend() throws {
        let next = RepeatRule.weekdays.nextRun(after: try october(30, 9, 0, 5), from: try october(30, 9), in: calendar)
        #expect(next == (try november(2, 9)))
    }

    @Test("A weekly task runs next on the same weekday a week later")
    func weekly() throws {
        let next = RepeatRule.weekly.nextRun(after: try october(28, 9, 0, 5), from: try october(28, 9), in: calendar)
        #expect(next == (try november(4, 9)))
    }

    @Test("Runs missed while the Mac slept are skipped, not caught up")
    func missedRunsAreSkipped() throws {
        let next = RepeatRule.daily.nextRun(after: try october(28, 14), from: try october(26, 9), in: calendar)
        #expect(next == (try october(29, 9)))
    }

    @Test("A missed weekly task keeps its weekday")
    func missedWeeklyKeepsWeekday() throws {
        let next = RepeatRule.weekly.nextRun(after: try october(28, 14), from: try october(19, 9), in: calendar)
        #expect(next == (try november(2, 9)))
    }

    @Test("The store keeps added tasks, saves updates and removes by id")
    func storeRoundTrip() throws {
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "ScheduledTaskTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = ScheduledTaskStore(fileURL: fileURL)
        #expect(try store.tasks().isEmpty)

        let summary = try store.add(prompt: "Summarise my calendar", firstRun: try october(29, 8), repeatRule: .weekdays)
        let report = try store.add(prompt: "Check the build", firstRun: try october(28, 18), repeatRule: .never)
        #expect([summary.id, report.id] == ["t1", "t2"])

        var ran = summary
        ran.lastResult = "Two meetings."
        ran.lastRun = try october(29, 8)
        ran.nextRun = try october(30, 8)
        try store.update(ran)
        #expect(try store.tasks() == [report, ran])

        #expect(try store.remove(id: "t2") == report)
        #expect(try store.remove(id: "t9") == nil)
        #expect(try ScheduledTaskStore(fileURL: fileURL).tasks() == [ran])
    }
}
