# Setup
The one-screen setup window shown when Accessibility access or the Dock gap is missing.

## Files
- `SetupWindow.swift`: the charcoal window; closing it before setup is finished quits macobar.
- `SetupView.swift`: the layout of the screen: wordmark, serif headline, miniature Dock, two steps, finish button.
- `SetupModel.swift`: which steps are done; asks for Accessibility and adds the gap to the Dock.
- `SetupStepRow.swift`: one numbered step with its explanation and button (upcoming / current / done).
- `MiniDockView.swift`: a monochrome miniature Dock that opens a gap after Finder and slides the field in when step 2 completes.
- `SetupButtonStyle.swift`: cream-filled pill for the next action, outlined pill otherwise.
- `SetupStyle.swift`: the palette (charcoal, graphite, smoke, cream, ash), type scale and motion.

## Public surface
- `SetupModel(gapReserver:fieldWidth:)`, `isFinished`
- `SetupWindow(model:)`, `show()`

## Design rules
- Monochrome only: charcoal and cream. No accent colours, no gradients.
- New York serif for the single headline and step numerals; SF Pro for everything else.
- Only one cream-filled button at a time: whichever action comes next.
- The miniature Dock opening is the one big motion. The mark bounces only while waiting on System Settings.

## Depends on
Dock (`DockGapReserver`), Permissions, Brand.
