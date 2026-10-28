import Foundation
import Synchronization
import UserNotifications

/// Runs due scheduled tasks one at a time, unattended, and reports each result in a notification.
final class TaskScheduler: Sendable {
    /// Longest wait between checks, so tasks added meanwhile are noticed within a minute.
    private static let longestWait = 60.0
    /// Longest result kept and shown, in characters.
    private static let maxResultLength = 500
    /// Put before each prompt, so Macie doesn't end a run with a question nobody will answer.
    private static let unattendedNote = """
        This is a scheduled task running while nobody is watching: don't ask questions, and if a step is declined, \
        say what couldn't be done. Reply with a short result for a notification.
        """

    /// Answers each task's prompt; a Macie of its own, so runs never mix into the chat.
    private let responder: any ChatResponder
    /// Where the tasks are kept.
    private let store: ScheduledTaskStore
    /// The running check loop, if started.
    private let loop = Mutex<Task<Void, Never>?>(nil)

    /// Creates a scheduler that runs the tasks in `store` with `responder`.
    init(responder: any ChatResponder, store: ScheduledTaskStore = ScheduledTaskStore()) {
        self.responder = responder
        self.store = store
    }

    /// Starts checking for due tasks, replacing any earlier loop.
    func start() {
        let task = Task { await self.runUntilCancelled() }
        loop.withLock { running in
            running?.cancel()
            running = task
        }
    }

    /// Stops checking and cancels the task running now, if any; that run isn't retried.
    func stop() {
        loop.withLock { running in
            running?.cancel()
            running = nil
        }
    }

    /// Runs whatever is due, then sleeps until the next task is due (at most a minute), until cancelled.
    private func runUntilCancelled() async {
        while !Task.isCancelled {
            while !Task.isCancelled, let task = nextDueTask(), let advanced = try? advance(task) {
                await run(advanced)
            }
            try? await Task.sleep(for: .seconds(secondsUntilNextCheck()))
        }
    }

    /// The soonest task whose time has come, read fresh so tasks cancelled meanwhile are skipped; nil when the file can't be read.
    private func nextDueTask() -> ScheduledTask? {
        (try? store.tasks())?.first { $0.nextRun <= .now }
    }

    /// Moves `task` on to its next run, or removes it when it doesn't repeat, before it runs, so it runs at most once
    /// even if macobar quits mid-run; a failed save throws, and the task waits for the next check instead of running.
    private func advance(_ task: ScheduledTask) throws -> ScheduledTask {
        guard let nextRun = task.repeatRule.nextRun(after: .now, from: task.nextRun, in: .current) else {
            _ = try store.remove(id: task.id)
            return task
        }
        var advanced = task
        advanced.nextRun = nextRun
        try store.update(advanced)
        return advanced
    }

    /// Seconds until the soonest task is due, between 1 and `longestWait`.
    private func secondsUntilNextCheck() -> Double {
        let soonest = (try? store.tasks())?.first?.nextRun.timeIntervalSinceNow ?? Self.longestWait
        return min(max(soonest, 1), Self.longestWait)
    }

    /// Runs `task`, keeps the result on it while it's still scheduled, and posts the result.
    private func run(_ task: ScheduledTask) async {
        let startedAt = Date.now
        let result = await answer(to: Self.unattendedNote + "\n\n" + task.prompt)
        guard !Task.isCancelled else { return }
        var finished = task
        finished.lastResult = result
        finished.lastRun = startedAt
        try? store.update(finished)
        await notify(prompt: task.prompt, result: result)
    }

    /// Macie's whole answer to `prompt`, shortened; approval requests are declined since nobody is watching.
    private func answer(to prompt: String) async -> String {
        var text = ""
        do {
            for try await event in responder.reply(to: prompt) {
                switch event {
                case .text(let more): text += more
                case .activity: break
                case .approval(let request): request.decide(.deny)
                }
            }
        } catch {
            text = "Couldn't finish: \(error.localizedDescription)"
        }
        let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return "Done." }
        return answer.count <= Self.maxResultLength ? answer : String(answer.prefix(Self.maxResultLength)) + "…"
    }

    /// Posts `result` as a notification from Macie; does nothing when notifications are off, since the result is stored anyway.
    private func notify(prompt: String, result: String) async {
        let notifications = UNUserNotificationCenter.current()
        guard (try? await notifications.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = "Macie"
        content.subtitle = prompt
        content.body = result
        content.sound = .default
        try? await notifications.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
