# Schedule
Prompts Macie runs on her own later or on repeat, with each result shown in a notification.

## Files
- `ScheduledTask.swift`: one task: id ("t3"), prompt, next run, repeat rule, last result and last run.
- `RepeatRule.swift`: `never`, `hourly`, `daily`, `weekdays` (Monday to Friday, whatever the locale's weekend), `weekly`, and the pure next-run rule (tested).
- `ScheduledTaskStore.swift`: the tasks in `~/Library/Application Support/macobar/scheduled-tasks.json`: list, add, remove, update; atomic writes (tested).
- `TaskScheduler.swift`: wakes when the soonest task is due (at most every 60 s), runs due tasks one at a time through a `ChatResponder`, saves the result and next run, and posts the result as a notification.

## Public surface
- `ScheduledTaskStore(fileURL:)`: `tasks()`, `add(prompt:firstRun:repeatRule:)`, `remove(id:)`, `update(_:)`
- `RepeatRule.nextRun(after:from:in:)`
- `TaskScheduler(responder:store:)`, `start()`, `stop()`

## How a task runs
1. Every task whose next run has passed runs, soonest first, one at a time.
2. Before it runs, its next run is saved (a task that doesn't repeat is removed), so it runs at most once. If that save fails, it waits for the next check instead.
3. The prompt goes to Macie with a note that nobody is watching, in a fresh conversation: the scheduler's Agent is built with `remembersConversation: false` (wired in App), so one task's content can't steer the next. Reply text is collected; activities are ignored; every approval request is declined. Tools the user chose to Always Allow still run, but only until the run reads outside content (a page, file, screen, email or remote server); after that they ask and so are declined. When MCP servers are connected, their tools count as outside content from the start, so Always Allow doesn't apply at all.
4. The result (cut to 500 characters) and run time are saved on a repeating task that's still scheduled.
5. A notification titled "Macie" shows the prompt and the result. If notifications are off, the result is only stored.

## Gotchas
- The file is the shared state: tools are stateless and read it on every call, and the scheduler reads it on every check. A lock serialises changes within the app.
- The next run keeps the scheduled time of day but counts from now, so runs missed while the Mac slept or macobar was closed run once, not as a burst.
- Times are local and follow the Mac's current time zone; a daily 9:00 task stays at 9:00 after travel or DST.
- Stopping the scheduler cancels the task running now; it isn't retried, since what it already did can't be undone.
- Prompts run without the chat's conversation or any earlier run's, so they must stand alone.
- `schedule_task` asks every time, so a scheduled run can't schedule more tasks.

## Tested by
`MacobarTests/ScheduledTaskTests.swift`.

## Depends on
ChatBar (`ChatResponder`, `ReplyEvent`, `ApprovalRequest`), UserNotifications.
