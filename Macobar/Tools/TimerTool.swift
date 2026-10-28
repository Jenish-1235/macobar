import Foundation
import UserNotifications

/// Sets a timer that ends with a notification.
struct SetTimerTool: Tool {
    let name = "set_timer"
    let description = """
        Shows a notification after a number of minutes (up to 24 hours). Use it for "remind me in…" or "set a timer \
        for…".
        """
    var parameters: JSONValue {
        Schema.object([
            "minutes": Schema.number("Minutes from now, over 0 and at most 1440; fractions allowed."),
            "message": Schema.string("Notification text."),
        ], required: ["minutes", "message"])
    }

    func activity(for input: ToolInput) -> String {
        "Setting a timer for \(input.number("minutes")?.formatted() ?? "?") min"
    }

    func run(_ input: ToolInput) async throws -> String {
        guard let minutes = input.number("minutes"), minutes > 0, minutes <= 1440 else {
            throw ToolError("minutes must be more than 0 and at most 1440.")
        }
        let message = try input.requiredString("message")
        let notifications = UNUserNotificationCenter.current()
        guard try await notifications.requestAuthorization(options: [.alert, .sound]) else {
            throw ToolError("Notifications are off for macobar. The user can allow them in System Settings → Notifications → macobar.")
        }
        let content = UNMutableNotificationContent()
        content.title = "Macie"
        content.body = message
        content.sound = .default
        let delay = minutes * 60
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        try await notifications.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger))
        let fireDate = Date.now.addingTimeInterval(delay)
        let day: Date.FormatStyle.DateStyle = Calendar.current.isDateInToday(fireDate) ? .omitted : .abbreviated
        return "Timer set. It will go off at \(fireDate.formatted(date: day, time: .shortened))."
    }
}
