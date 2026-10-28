import CoreGraphics

/// One thing the user is asked to do in a guided walkthrough, which `UserProgressWaiter` watches for.
enum UserExpectation: Equatable, Sendable {
    /// A left click inside this rect, in global screen points from the top-left of the main display.
    case clickIn(CGRect)
    /// Another app coming to the front.
    case appChange
    /// The front window changing: another window, a new title, or the window closing.
    case windowChange
    /// A menu opening in the front app, from the menu bar or a context menu.
    case menuOpen
    /// This text showing in the front window, matched case-insensitively.
    case textAppears(String)
    /// Any key being pressed.
    case anyKey

    /// What is awaited, as a phrase to follow "waiting for", e.g. "a click in the marked area".
    var summary: String {
        switch self {
        case .clickIn: "a click in the marked area"
        case .appChange: "another app to come to the front"
        case .windowChange: "the front window to change"
        case .menuOpen: "a menu to open"
        case .textAppears(let text): "“\(text)” to appear"
        case .anyKey: "a key press"
        }
    }
}
