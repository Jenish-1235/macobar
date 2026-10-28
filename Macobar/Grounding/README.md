# Grounding
Lets Macie see the screen as numbered targets (Set-of-Mark) and point at, click, scroll and drag anything, including web pages and Electron apps.

## Files
- `ScreenMarks.swift`: one look: captures, finds targets, picks marks, draws them, and stores them.
- `ScreenImageCapture.swift`: `LookTarget` (`screen`, `front_window`) and the ScreenCaptureKit capture: the display under the pointer with macobar's windows left out, or the front app's window; returns the image and the area it shows.
- `AccessibilityTargets.swift`: walks the front window (one batched attribute read per element, at most 4,000 elements) for buttons, links, tabs, fields, checkboxes, menu items, rows and short static text, cut to what is visible (window and scroll areas).
- `RecognizedTextTargets.swift`: Vision OCR lines as targets, for what Accessibility can't see.
- `MarkSelection.swift`: drops duplicates, keeps the best 150, numbers them in reading order (tested).
- `MarkAnnotator.swift`: draws a thin outline and a numbered badge per mark (CoreGraphics and CoreText only, safe off the main actor) and encodes JPEG at most 1280 px.
- `ScreenMarkStore.swift`: the latest marks, so "mark 12" means something until they expire (tested).
- `MarkKind.swift`, `ScreenTarget.swift`, `ScreenMark.swift`: what a target is, and a numbered target with its list line.
- `PointReference.swift`: a tool's place argument, `mark` or `x` and `y` with an optional prefix (`from_`, `to_`), its schema, and resolving it to a point (tested).
- `ScreenCoordinates.swift`: every conversion between screen points, mouse-event locations, AppKit, Vision boxes and image pixels (tested).
- `MouseEvents.swift`: real mouse clicks, scrolls and drags with CGEvent, putting the pointer back afterwards; refuses points off screen or inside macobar's windows. A click's press and release, and a drag's press and release, are each checked in the same main-actor step that posts them.

## Public surface
- `ScreenMarks.look(at:storingIn:)` → marks, annotated `ToolImage`, subject, area
- `ScreenMarkStore()`, `replace(with:at:)`, `mark(_:at:)`
- `ScreenMark` (`number`, `target`, `center`, `name`, `summary`), `ScreenTarget` (`kind`, `label`, `frame`, `source`)
- `PointReference.parameters(prefix:place:)`, `optional(in:prefix:)`, `required(in:prefix:)`, `resolve(in:at:)`, `name(in:)`
- `MouseEvents.requireActionable(_:)`, `pointerLocation`, `click(_:count:at:)`, `scroll(_:lines:at:)`, `drag(from:to:)`

## Coordinates
- Screen points: global, top-left origin on the main screen, as Accessibility, SCWindow and CGWindowList report them. Every mark frame and every `x`/`y` uses them.
- Mouse events use the same space, so `ScreenCoordinates.eventLocation(for:)` changes nothing; it exists so the assumption is written down and tested.
- Vision boxes are normalized with a bottom-left origin; drawing uses image pixels with a bottom-left origin; AppKit windows use a bottom-left origin from the main screen's bottom.

## Rules
- Recognized text is dropped when it overlaps an Accessibility target with IoU > 0.5, and any text is dropped when a control holds 90% of it and one label contains the other (a button and its own title are one mark). Other text inside a control, such as an editor's lines, keeps its marks.
- Over 150 marks, controls beat text, labelled beats unlabelled, larger beats smaller. Targets under 4 points wide or tall are skipped.
- Marks expire 2 minutes after the look, or at the next look.
- `scroll` with no place scrolls under the pointer, and refuses when the pointer is over macobar.
- A click's press and release, and a drag's press, are checked against macobar's windows in the same main-actor step that posts them, so an approval card that appears after the tool's own check can't be clicked.
- A drag cancelled partway, or whose end is now off screen or over a macobar window, releases the button back where it started.
- `click_mark` presses an Accessibility mark directly (AXPress on the element under its centre, or a near ancestor of the same kind) for a single left click, and never presses an element owned by macobar; otherwise it posts real events.

## Gotchas
- Posting mouse events needs Accessibility (already granted in setup); capture needs Screen Recording.
- The own-window check uses `NSApplication.shared.windows` that take the mouse, so the click-through Overlay panels don't block every click, which a CGWindowList bounds check would.
- Only the front app's focused window is walked; other windows, the menu bar and the Dock show up through OCR text only.

## Tested by
`MacobarTests/GroundingTests.swift`.

## Depends on
Tools (`ToolError`, `ToolInput`, `Schema`, `AccessibilityElement`, `RunningApps`), ModelClient (`JSONValue`, `ToolImage`).
