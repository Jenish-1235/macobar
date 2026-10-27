# Permissions
Checks and requests the macOS privacy permissions macobar needs.

## Files
- `AccessibilityPermission.swift`: reports whether access is granted, shows the system prompt, opens the right System Settings pane, and waits for the grant.

## Public surface
- `AccessibilityPermission.isGranted`
- `AccessibilityPermission.requestAccess()`, `openSettings()`
- `AccessibilityPermission.waitUntilGranted() async`

## Gotchas
- The grant is tied to the app's signature. Builds signed with the same team keep it; unsigned builds lose it on every rebuild.
- Running the binary from Terminal inherits Terminal's own Accessibility grant, which is handy for development.
