import Foundation

/// Schedules a prompt for Macie to run later or on repeat, reporting the result in a notification.
struct ScheduleTaskTool: Tool {
    /// Name the model calls it by.
    let name = "schedule_task"
    /// When to call it and what it returns.
    let description = """
        Schedules a prompt for you to run later, once or on repeat, with the result in a notification. Use it for \
        work at a set time or regularly; for a plain reminder use set_timer. Runs can't ask for approval, so steps \
        needing it are declined unless the user chose Always Allow for that tool.
        """

    /// Takes the prompt, the first run time and the repeat rule.
    var parameters: JSONValue {
        Schema.object([
            "prompt": Schema.string("Complete instruction; it runs without this conversation."),
            "at": Schema.string("First run, future ISO 8601 local date-time, e.g. 2026-10-29T08:00."),
            "repeat": Schema.oneOf(RepeatRule.allCases.map(\.rawValue), "Defaults to never."),
        ], required: ["prompt", "at"])
    }

    /// Adds work that runs again and again without the user watching, using whatever they always allow, so it asks every time.
    func risk(for input: ToolInput) -> ToolRisk {
        .confirmEveryTime
    }

    /// Names the prompt being scheduled.
    func activity(for input: ToolInput) -> String {
        "Scheduling “\(input.string("prompt") ?? "a task")”"
    }

    /// Validates the arguments and saves the task.
    func run(_ input: ToolInput) async throws -> String {
        let prompt = try input.requiredString("prompt")
        let firstRun = try localDateTime(from: input.requiredString("at"))
        guard firstRun > .now else {
            throw ToolError("\"at\" is in the past. Pass a future local date-time, e.g. 2026-10-29T08:00.")
        }
        let repeatName = input.string("repeat") ?? RepeatRule.never.rawValue
        guard let repeatRule = RepeatRule(rawValue: repeatName) else {
            throw ToolError("Unknown repeat \"\(repeatName)\". Use one of: \(RepeatRule.allCases.map(\.rawValue).joined(separator: ", ")).")
        }
        let task = try ScheduledTaskStore().add(prompt: prompt, firstRun: firstRun, repeatRule: repeatRule)
        return "Scheduled \(task.id): first run \(readable(task.nextRun)), \(repeatSummary(task.repeatRule))."
    }
}

/// Lists the tasks scheduled with schedule_task.
struct ListScheduledTasksTool: Tool {
    /// Name the model calls it by.
    let name = "list_scheduled_tasks"
    /// When to call it and what it returns.
    let description = """
        Lists tasks scheduled with schedule_task: id, prompt, next run, repeat and last result. Use it for what's \
        scheduled, how a task went, or a task's id.
        """

    /// Takes no arguments.
    var parameters: JSONValue { Schema.object() }

    /// Describes the lookup.
    func activity(for input: ToolInput) -> String { "Checking scheduled tasks" }

    /// Its result carries earlier runs' results, which can quote pages, files or emails those runs read.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        true
    }

    /// One line per scheduled task.
    func run(_ input: ToolInput) async throws -> String {
        let tasks = try ScheduledTaskStore().tasks()
        guard !tasks.isEmpty else { return "No tasks are scheduled." }
        return tasks.map { task in
            var line = "• \(task.id): “\(task.prompt)”, next \(readable(task.nextRun)), \(repeatSummary(task.repeatRule))"
            if let lastRun = task.lastRun, let lastResult = task.lastResult {
                line += ". Last run \(readable(lastRun)): \(lastResult)"
            }
            return line
        }.joined(separator: "\n")
    }
}

/// Cancels a scheduled task so it never runs again.
struct CancelScheduledTaskTool: Tool {
    /// Name the model calls it by.
    let name = "cancel_scheduled_task"
    /// When to call it and what it returns.
    let description = "Cancels a task scheduled with schedule_task; get its id from list_scheduled_tasks first."

    /// Takes the task's id.
    var parameters: JSONValue {
        Schema.object(["id": Schema.string("Task id, e.g. \"t3\".")], required: ["id"])
    }

    /// Removes something the user set up, so it asks once.
    func risk(for input: ToolInput) -> ToolRisk {
        .confirmOnce
    }

    /// Names the task being cancelled.
    func activity(for input: ToolInput) -> String {
        "Cancelling scheduled task \(input.string("id") ?? "")"
    }

    /// Removes the task.
    func run(_ input: ToolInput) async throws -> String {
        let id = try input.requiredString("id")
        guard let task = try ScheduledTaskStore().remove(id: id) else {
            throw ToolError("No scheduled task has the id \"\(id)\". Call list_scheduled_tasks for the current ids.")
        }
        return "Cancelled \(task.id): “\(task.prompt)”."
    }
}

/// `text` read as an ISO 8601 date-time, in local time unless it carries an offset.
private func localDateTime(from text: String) throws -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    for format in ["yyyy-MM-dd'T'HH:mm:ssXXXXX", "yyyy-MM-dd'T'HH:mmXXXXX", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm"] {
        formatter.dateFormat = format
        if let date = formatter.date(from: text) { return date }
    }
    throw ToolError("\"at\" must be an ISO 8601 local date-time like 2026-10-29T08:00, not “\(text)”.")
}

/// `date` as a short local date and time.
private func readable(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
}

/// How often a task repeats, in words.
private func repeatSummary(_ rule: RepeatRule) -> String {
    switch rule {
    case .never: "runs once"
    case .hourly: "repeats hourly"
    case .daily: "repeats daily"
    case .weekdays: "repeats on weekdays"
    case .weekly: "repeats weekly"
    }
}
