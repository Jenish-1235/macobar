import Foundation

/// How often a scheduled task runs again.
enum RepeatRule: String, Codable, Sendable, CaseIterable {
    /// Runs once.
    case never
    /// Every hour, at the same minute.
    case hourly
    /// Every day, at the same time.
    case daily
    /// Monday to Friday, at the same time.
    case weekdays
    /// Every week, on the same day and time.
    case weekly

    /// Sunday and Saturday as `Calendar` numbers them, skipped by `weekdays` whatever the locale's weekend.
    private static let weekendDays: Set<Int> = [1, 7]

    /// The first run after `now` that keeps `scheduled`'s time (and weekday, for weekly), or nil for `never`.
    /// Counting from `now` means runs missed while the Mac slept are skipped, not caught up one by one.
    func nextRun(after now: Date, from scheduled: Date, in calendar: Calendar) -> Date? {
        let time = calendar.dateComponents([.hour, .minute, .second, .weekday], from: scheduled)
        switch self {
        case .never:
            return nil
        case .hourly:
            return calendar.nextDate(after: now, matching: DateComponents(minute: time.minute, second: time.second), matchingPolicy: .nextTime)
        case .daily:
            return nextDay(after: now, at: time, in: calendar)
        case .weekdays:
            var next = nextDay(after: now, at: time, in: calendar)
            while let day = next, Self.weekendDays.contains(calendar.component(.weekday, from: day)) {
                next = nextDay(after: day, at: time, in: calendar)
            }
            return next
        case .weekly:
            let matching = DateComponents(hour: time.hour, minute: time.minute, second: time.second, weekday: time.weekday)
            return calendar.nextDate(after: now, matching: matching, matchingPolicy: .nextTime)
        }
    }

    /// The first moment after `date` at `time`'s hour, minute and second.
    private func nextDay(after date: Date, at time: DateComponents, in calendar: Calendar) -> Date? {
        calendar.nextDate(after: date, matching: DateComponents(hour: time.hour, minute: time.minute, second: time.second), matchingPolicy: .nextTime)
    }
}
