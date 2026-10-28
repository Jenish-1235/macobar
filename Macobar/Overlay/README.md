# Overlay
Macie draws on the screen: short-lived, animated marks that point things out and guide the user, then fade away.

## Files
- `ScreenOverlay.swift`: the controller. `draw(_:duration:)` replaces whatever is drawn and fades it out after `duration`; `clear()` fades it out now. Makes one panel per screen on first use, rebuilds them when screens change, and hides them once nothing is drawn.
- `DrawingPanel.swift`: a transparent, borderless, click-through panel covering one screen, on every Space and over full-screen apps.
- `OverlayBoard.swift`: the drawing every screen shows (`OverlayDrawing`: an id and its shapes), observed by the canvases.
- `OverlayCanvas.swift`: one screen's view: moves each shape into that screen's coordinates and staggers them in.
- `OverlayMarkView.swift`: one shape, drawing itself in. `LabelBubble.swift`: the text bubble, led by Macie's face, kept on screen. `PointerDot.swift`: Macie's dot.
- `OverlayPaths.swift`: the outlines for arrows, freehand paths, highlight rings and spotlight holes.
- `OverlayStyle.swift`: every colour, size and animation used above, including `labelMacieSize`, the width of Macie at the start of each label.
- `OverlayShape.swift`: the shapes (`highlight`, `circle`, `arrow`, `label`, `path`, `spotlight`, `pointer`), their kind names, and `mapped(_:)` to move one between coordinate spaces (tested).
- `OverlayCoordinates.swift`: top-left main-screen points to AppKit global points, and AppKit global points to a screen's view space (tested).
- `DrawingRequest.swift`: reads and checks a `draw_on_screen` call's `shapes` and `duration`, with errors the model can act on (tested).

## Public surface
- `ScreenOverlay()`, `draw(_ shapes: [OverlayShape], duration: Duration)`, `clear()`; shapes in AppKit global coordinates (bottom-left origin)
- `OverlayShape`, `OverlayShape.Kind`, `mapped(_:)`
- `OverlayCoordinates.appKitPoint(fromTopLeft:mainScreenHeight:)`, `viewPoint(fromAppKit:in:)`
- `DrawingRequest(arguments:)` → `shapes`, `duration`; `shapeLimit` (20), `textLimit` (80), `defaultSeconds` (6), `longestSeconds` (60)

## Coordinates
1. The model gives points from the top-left of the main screen (the one with the menu bar), the same space Accessibility frames use.
2. The tools flip them into AppKit's bottom-left global space before calling `draw`.
3. Each screen's canvas moves them into its own top-left view space, so a shape that crosses screens is drawn in parts.

## Design rules
- Native first: the user's accent colour, with a soft white edge and a glow so marks read on any background. No brand colour.
- Marks draw in (~0.35 s spring): strokes trace themselves, highlights settle from slightly larger, labels grow from their base, the pointer rises from the Dock to its point and pulses. Shapes drawn together appear in order, 0.08 s apart.
- Every label bubble starts with Macie's face, so on-screen text is always visibly hers and never passes for system or app UI.
- Reduce Motion: no tracing, travel or pulse; drawings only cross-fade.
- Each `draw` replaces the last drawing (it cross-fades); a drawing fades out after its duration (default 6 s, at most 60 s).

## Gotchas
- Panels sit at the Dock's window level: over app windows and the Dock, under the chat field and reply card (one level up) and the menu bar.
- Panels ignore the mouse and never take focus, so the user can keep working through a drawing.
- A spotlight dims every screen except its hole, so on other screens it dims the whole screen.
- The pointer is drawn only on the screen that holds its point.
- Screen tools don't capture macobar's windows, so drawings never show up in screenshots Macie takes.

## Tested by
`MacobarTests/OverlayTests.swift`.

## Depends on
ModelClient (`JSONValue`, for `DrawingRequest`), Brand (`Macie`, in label bubbles).
