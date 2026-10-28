import ApplicationServices

/// What a numbered mark on screen is, as the model reads it.
enum MarkKind: String, Sendable {
    /// A push button.
    case button
    /// A checkbox or switch.
    case checkbox
    /// A radio button.
    case radio
    /// A pop-up or menu button.
    case popUp = "pop-up"
    /// A tab in a tab bar.
    case tab
    /// A link in a web page or app.
    case link
    /// An item in a menu.
    case menuItem = "menu item"
    /// A field or area that takes typed text.
    case textField = "text field"
    /// A slider.
    case slider
    /// A disclosure triangle.
    case disclosure
    /// A row in a list, table or outline.
    case row
    /// Text on screen, from Accessibility or recognized in the screenshot.
    case text

    /// The kind for an Accessibility role and subrole, or nil when such an element isn't worth a mark.
    init?(role: String, subrole: String?) {
        switch role {
        case kAXButtonRole: self = .button
        case kAXCheckBoxRole: self = .checkbox
        case kAXRadioButtonRole: self = subrole == "AXTabButton" ? .tab : .radio
        case kAXPopUpButtonRole, kAXMenuButtonRole: self = .popUp
        case "AXLink": self = .link
        case kAXMenuItemRole: self = .menuItem
        case kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole: self = .textField
        case kAXSliderRole: self = .slider
        case kAXDisclosureTriangleRole: self = .disclosure
        case kAXRowRole: self = .row
        case kAXStaticTextRole: self = .text
        default: return nil
        }
    }

    /// Whether the user acts on it by clicking or typing, rather than only reading it.
    var isActionable: Bool { self != .text }
}
