import Foundation

/// The activity entries from one calendar day, as the History window groups them.
struct ActivityDay: Identifiable, Equatable {
    /// The start of the day.
    let date: Date
    /// That day's entries, newest first.
    fileprivate(set) var entries: [ActivityEntry]

    /// The day itself.
    var id: Date { date }

    /// `entries`, newest first, split into days in `calendar`, newest day first.
    static func grouping(_ entries: [ActivityEntry], in calendar: Calendar = .current) -> [ActivityDay] {
        var days: [ActivityDay] = []
        for entry in entries {
            let day = calendar.startOfDay(for: entry.date)
            if days.last?.date == day {
                days[days.count - 1].entries.append(entry)
            } else {
                days.append(ActivityDay(date: day, entries: [entry]))
            }
        }
        return days
    }
}
