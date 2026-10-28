# Guide
Guide mode: Macie teaches step by step inside any app. She points at the next thing, says what to do, then waits until the user actually does it before moving on.

## Files
- `UserExpectation.swift`: what the user is asked to do: click inside a rect, switch apps, change the front window, open a menu, make some text appear, or press any key. `summary` phrases it for activity lines and timeouts.
- `UserProgressWaiter.swift`: waits for an expectation, racing it against a timeout (default 60 s, 1 to 300 s) and stopping when its task is cancelled. Returns a `WaitOutcome`.
- `WaitOutcome.swift`: how a wait ended: `matched` with what the user did (e.g. "Opened the File menu"), `timedOut`, or `cancelled`.
- `FrontAppProbe.swift`: Accessibility reads of the frontmost app: its focused window, the menu open in it, and whether some text shows in the window. It never reads macobar's own windows (`frontWindow` is nil while macobar is in front) and never searches a password field's value.

## Public surface
- `UserProgressWaiter.wait(for:timeout:) async throws -> WaitOutcome` (throws only when watching can't start)
- `UserProgressWaiter.timeout(seconds:)`, `UserProgressWaiter.isClick(at:inside:primaryScreenHeight:)`
- `UserExpectation`, `WaitOutcome`

## How each step is watched
| Expectation | How |
|---|---|
| Click in a rect | Global `leftMouseDown` monitor; the AppKit location is flipped to top-left-origin global points before hit-testing |
| App change | Frontmost app's pid polled at 4 Hz |
| Window change | Frontmost app's focused window polled at 4 Hz: another element, a new title, or no window |
| Menu open | Polled at 4 Hz: a menu bar item is `AXSelected`, or the app's focused element is an `AXMenu`/`AXMenuItem` (context menus) |
| Text appears | Front window's titles, values (never a password field's) and descriptions searched at 2 Hz, case-insensitively, up to 3,000 elements |
| Any key | Global `keyDown` monitor; which key is never recorded |

## Gotchas
- Rects are global screen points from the top-left of the main display, the same space as Accessibility frames. AppKit events are bottom-left-origin, so `isClick` flips them by the main display's height; displays above the main one have negative y.
- Global monitors never see events aimed at macobar's own windows, so an on-screen pointer or drawing must let clicks pass through to the app below.
- Monitors are removed in a `defer`, so a timeout or cancellation never leaves one behind. Polls stop at the next `Task.sleep`.
- Text that is already showing when the wait begins matches straight away, and the outcome says it was already there.
- Needs Accessibility access (global key monitoring and every AX read); `wait` checks it first.

## Tested by
`MacobarTests/GuideTests.swift`.

## Depends on
Tools (`AccessibilityElement`, `RunningApps`, `ToolError`, `appOtherThanMacobar`, `isSecureTextField`).
