import EventKit
import Foundation

/// Lists the user's calendar events over a span of days.
struct ListEventsTool: Tool {
    /// Name the model calls it by.
    let name = "list_events"
    /// When to use it and what it returns.
    let description = "Lists events from all the user's calendars. Use it for their schedule, meetings or free time."

    /// The start date and number of days to cover.
    var parameters: JSONValue {
        Schema.object([
            "start": Schema.string("ISO 8601 date or date-time, local. Defaults to today."),
            "days": Schema.integer("Days to cover, 1–31. Defaults to 1."),
        ])
    }

    /// Its result carries outside text the model will read, so later risky actions always ask.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        true
    }

    /// Describes the lookup.
    func activity(for input: ToolInput) -> String {
        "Checking your calendar"
    }

    /// Fetches and formats the events in the requested span.
    func run(_ input: ToolInput) async throws -> String {
        let start = try input.string("start").map { try date(from: $0, argument: "start") } ?? Calendar.current.startOfDay(for: .now)
        let days = min(max(input.integer("days") ?? 1, 1), 31)
        guard let end = Calendar.current.date(byAdding: .day, value: days, to: start) else {
            throw ToolError("Couldn't work out the end of a \(days)-day span from \(start).")
        }
        let store = try await authorizedEventStore(for: .event)
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .sorted { $0.startDate < $1.startDate }
        guard !events.isEmpty else { return "No events from \(dateRange(from: start, to: end, allDay: false))." }
        return events.map { event in
            var line = "• \(dateRange(from: event.startDate, to: event.endDate, allDay: event.isAllDay)) — \(event.title ?? "Untitled")"
            if let location = event.location, !location.isEmpty { line += " @ \(location)" }
            if let calendar = event.calendar { line += " [\(calendar.title)]" }
            return line
        }.joined(separator: "\n")
    }
}

/// Adds an event to the user's default calendar.
struct CreateEventTool: Tool {
    /// Name the model calls it by.
    let name = "create_event"
    /// When to use it and what it returns.
    let description = """
        Adds an event to the user's default calendar when they ask to schedule, book or add something to it.
        """

    /// The event's title, times and details.
    var parameters: JSONValue {
        Schema.object([
            "title": Schema.string("Title."),
            "start": Schema.string("ISO 8601 local date-time, e.g. 2026-10-28T15:00."),
            "end": Schema.string("ISO 8601 date-time. Defaults to start + 1 hour."),
            "location": Schema.string("Location."),
            "notes": Schema.string("Notes."),
            "all_day": Schema.boolean("All-day event."),
        ], required: ["title", "start"])
    }

    /// Changes the calendar, so asks once.
    func risk(for input: ToolInput) -> ToolRisk {
        .confirmOnce
    }

    /// Describes the event being added.
    func activity(for input: ToolInput) -> String {
        "Adding “\(input.string("title") ?? "an event")” to your calendar"
    }

    /// Saves the event and confirms when it is.
    func run(_ input: ToolInput) async throws -> String {
        let title = try input.requiredString("title")
        let start = try date(from: input.requiredString("start"), argument: "start")
        let isAllDay = input.bool("all_day")
        let end = try input.string("end").map { try date(from: $0, argument: "end") } ?? (isAllDay ? start : start.addingTimeInterval(3600))
        guard end >= start else { throw ToolError("\"end\" must not be before \"start\".") }
        let store = try await authorizedEventStore(for: .event)
        guard let calendar = store.defaultCalendarForNewEvents else {
            throw ToolError("There's no default calendar. Ask the user to choose one in Calendar → Settings → General.")
        }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.isAllDay = isAllDay
        event.location = input.string("location")
        event.notes = input.string("notes")
        event.calendar = calendar
        try store.save(event, span: .thisEvent, commit: true)
        return "Created “\(title)”, \(dateRange(from: start, to: end, allDay: isAllDay)), in \(calendar.title)."
    }
}

/// Lists the user's reminders.
struct ListRemindersTool: Tool {
    /// Name the model calls it by.
    let name = "list_reminders"
    /// When to use it and what it returns.
    let description = "Lists the user's reminders (to-dos), soonest due first. Use it for what they need to do."

    /// Whether to include completed ones and which list to read.
    var parameters: JSONValue {
        Schema.object([
            "include_completed": Schema.boolean("Include completed ones."),
            "list": Schema.string("One list's name. Defaults to all."),
        ])
    }

    /// Its result carries outside text the model will read, so later risky actions always ask.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        true
    }

    /// Describes the lookup.
    func activity(for input: ToolInput) -> String {
        "Checking your reminders"
    }

    /// Fetches and formats the matching reminders.
    func run(_ input: ToolInput) async throws -> String {
        let store = try await authorizedEventStore(for: .reminder)
        let lists = try input.string("list").map { [try reminderList(named: $0, in: store)] }
        let predicate = input.bool("include_completed")
            ? store.predicateForReminders(in: lists)
            : store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: lists)
        let lines = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminderLines(reminders ?? []))
            }
        }
        guard !lines.isEmpty else { return "No reminders." }
        let shownLimit = 100
        let shown = lines.prefix(shownLimit).joined(separator: "\n")
        return lines.count > shownLimit ? shown + "\n…and \(lines.count - shownLimit) more." : shown
    }

    /// One line per reminder, soonest due first and undated last.
    private func reminderLines(_ reminders: [EKReminder]) -> [String] {
        let dated = reminders.map { reminder in
            (reminder, reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) })
        }
        return dated
            .sorted { ($0.1 ?? .distantFuture) < ($1.1 ?? .distantFuture) }
            .map { reminder, due in
                var line = "• \(reminder.title ?? "Untitled")"
                if let due {
                    let hasTime = reminder.dueDateComponents?.hour != nil
                    line += " — due \(due.formatted(date: .abbreviated, time: hasTime ? .shortened : .omitted))"
                }
                if let list = reminder.calendar { line += " [\(list.title)]" }
                if reminder.isCompleted { line += " (done)" }
                return line
            }
    }
}

/// Adds a reminder to one of the user's lists.
struct CreateReminderTool: Tool {
    /// Name the model calls it by.
    let name = "create_reminder"
    /// When to use it and what it returns.
    let description = """
        Adds a reminder (to-do) to Reminders when the user asks to be reminded of something or to add a task. A due \
        date-time also sets an alert at that time.
        """

    /// The reminder's title, due date, notes and list.
    var parameters: JSONValue {
        Schema.object([
            "title": Schema.string("Title."),
            "due": Schema.string("ISO 8601 date or date-time, local."),
            "notes": Schema.string("Notes."),
            "list": Schema.string("List name. Defaults to the default list."),
        ], required: ["title"])
    }

    /// Changes the reminders, so asks once.
    func risk(for input: ToolInput) -> ToolRisk {
        .confirmOnce
    }

    /// Describes the reminder being added.
    func activity(for input: ToolInput) -> String {
        "Adding the reminder “\(input.string("title") ?? "")”"
    }

    /// Saves the reminder and confirms where it went.
    func run(_ input: ToolInput) async throws -> String {
        let title = try input.requiredString("title")
        let store = try await authorizedEventStore(for: .reminder)
        let list = try input.string("list").map { try reminderList(named: $0, in: store) } ?? store.defaultCalendarForNewReminders()
        guard let list else { throw ToolError("There's no default reminders list. Pass \"list\" with a list name.") }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = input.string("notes")
        reminder.calendar = list
        var summary = "Created the reminder “\(title)” in \(list.title)"
        if let dueText = input.string("due") {
            let due = try date(from: dueText, argument: "due")
            let hasTime = dueText.contains("T")
            let parts: Set<Calendar.Component> = hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
            reminder.dueDateComponents = Calendar.current.dateComponents(parts, from: due)
            if hasTime { reminder.addAlarm(EKAlarm(absoluteDate: due)) }
            summary += ", due \(due.formatted(date: .abbreviated, time: hasTime ? .shortened : .omitted))"
        }
        try store.save(reminder, commit: true)
        return summary + "."
    }
}

/// An event store with full access to `entity`, or an error telling the user how to grant it.
private func authorizedEventStore(for entity: EKEntityType) async throws -> EKEventStore {
    let store = EKEventStore()
    let isGranted: Bool
    let settingsPane: String
    if entity == .event {
        isGranted = (try? await store.requestFullAccessToEvents()) == true
        settingsPane = "Calendars"
    } else {
        isGranted = (try? await store.requestFullAccessToReminders()) == true
        settingsPane = "Reminders"
    }
    guard isGranted else {
        throw ToolError("macobar can't access \(settingsPane). Ask the user to allow macobar in System Settings → Privacy & Security → \(settingsPane), then try again.")
    }
    return store
}

/// The reminders list called `name` (case-insensitive), or an error naming the lists there are.
private func reminderList(named name: String, in store: EKEventStore) throws -> EKCalendar {
    let lists = store.calendars(for: .reminder)
    guard let list = lists.first(where: { $0.title.caseInsensitiveCompare(name) == .orderedSame }) else {
        throw ToolError("There's no reminders list called “\(name)”. Lists: \(lists.map(\.title).joined(separator: ", ")).")
    }
    return list
}

/// Reads an ISO 8601 date or date-time given as `argument`, treating one without an offset as local time.
private func date(from text: String, argument: String) throws -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    for format in ["yyyy-MM-dd'T'HH:mm:ssXXXXX", "yyyy-MM-dd'T'HH:mmXXXXX", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
        formatter.dateFormat = format
        if let date = formatter.date(from: text) { return date }
    }
    throw ToolError("\"\(argument)\" must be an ISO 8601 date or date-time like 2026-10-28 or 2026-10-28T15:00, not “\(text)”.")
}

/// `start` to `end` in readable local time, as days only when `allDay`.
private func dateRange(from start: Date, to end: Date, allDay: Bool) -> String {
    let formatter = DateIntervalFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = allDay ? .none : .short
    return formatter.string(from: start, to: end) + (allDay ? " (all day)" : "")
}
