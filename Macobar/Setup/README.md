# Setup
The one-screen setup window shown when Accessibility access, the Dock gap or a model is missing, and the Connect screen for choosing a model.

## Files
- `SetupWindow.swift`: the charcoal window; closing it before setup is finished quits macobar.
- `SetupView.swift`: the layout of the screen: Macie and wordmark, serif headline, miniature Dock, three steps, finish button.
- `SetupModel.swift`: which steps are done; asks for Accessibility, adds the gap to the Dock, and records the connected provider.
- `SetupStepRow.swift`: one numbered step with its explanation and button (upcoming / current / done).
- `MiniDockView.swift`: a monochrome miniature Dock that opens a gap after Finder and slides the field in when step 2 completes.
- `SetupButtonStyle.swift`: cream-filled pill for the next action, outlined pill otherwise.
- `SetupStyle.swift`: the palette (charcoal, graphite, smoke, cream, ash), type scale, sizes and motion.
- `ConnectWindow.swift`: hosts the Connect screen as a sheet over setup (step 3) or as its own window (Change Model… in the Dock).
- `ConnectView.swift`: provider grid, API key with a "Get a key" link, model, and region or resource when needed; Cancel and Connect.
- `ConnectModel.swift`: the form state; Connect asks the provider for a one-word reply and only then saves the key and activates the account.
- `ProviderTile.swift`: one provider in the grid; the selected one is rimmed in cream with a check.
- `SetupTextField.swift`: a labelled field in the setup palette (plain or secure).

## Public surface
- `SetupModel(gapReserver:fieldWidth:connectedProvider:)`, `isFinished`, `modelDidConnect(_:)`
- `SetupWindow(model:onConnectModel:)`, `show()`
- `ConnectModel(store:onConnected:)`, `ConnectWindow(model:)`, `show(over:)`, `close()`

## Gotchas
- ChatGPT isn't offered yet; it joins the grid once Sign in with ChatGPT exists.
- An empty key field keeps the key already saved for that provider.

## Design rules
- Monochrome only: charcoal and cream. No accent colours, no gradients.
- New York serif for the single headline and step numerals; SF Pro for everything else.
- Only one cream-filled button at a time: whichever action comes next. Selection (provider tiles) is shown with a cream rim, never a fill.
- The miniature Dock opening is the one big motion. Macie asks (head tilt) while waiting on System Settings and smiles once setup is done.

## Depends on
Dock (`DockGapReserver`), Permissions, Brand, Providers, ModelClient.
