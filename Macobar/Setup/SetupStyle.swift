import SwiftUI

/// The setup screen's monochrome palette, type scale, sizes and motion.
enum SetupStyle {
    /// Window background: warm charcoal (#1A1918).
    static let charcoal = Color(red: 26 / 255, green: 25 / 255, blue: 24 / 255)
    /// Raised surfaces like the miniature Dock (#252422).
    static let graphite = Color(red: 37 / 255, green: 36 / 255, blue: 34 / 255)
    /// Hairlines and dividers (#3C3A36).
    static let smoke = Color(red: 60 / 255, green: 58 / 255, blue: 54 / 255)
    /// Primary text and the filled button (#EDE6D6).
    static let cream = Color(red: 237 / 255, green: 230 / 255, blue: 214 / 255)
    /// Secondary text.
    static let ash = cream.opacity(0.55)
    /// Text on cream.
    static let ink = charcoal

    /// Fixed size of the setup window.
    static let windowSize = CGSize(width: 720, height: 716)
    /// Space between the window edge and the content.
    static let margin: CGFloat = 56
    /// Width of the Connect screen.
    static let connectWidth: CGFloat = 600
    /// Space between the Connect screen's edge and its content.
    static let sheetMargin: CGFloat = 48
    /// Height of text fields and provider tiles.
    static let fieldHeight: CGFloat = 38
    /// Corner radius of text fields and provider tiles.
    static let fieldCornerRadius: CGFloat = 10

    /// The lowercase wordmark next to Macie.
    static let wordmarkFont = Font.system(size: 14, weight: .semibold)
    /// The one large serif headline.
    static let displayFont = Font.system(size: 44, weight: .regular, design: .serif)
    /// The Connect screen's serif headline.
    static let titleFont = Font.system(size: 32, weight: .regular, design: .serif)
    /// The line under the headline.
    static let ledeFont = Font.system(size: 15)
    /// Step numbers, set as serif italics.
    static let stepNumberFont = Font.system(size: 17, design: .serif).italic()
    /// Step titles.
    static let stepTitleFont = Font.system(size: 14, weight: .medium)
    /// Step explanations and quiet status text.
    static let detailFont = Font.system(size: 12.5)
    /// Text typed into fields.
    static let fieldFont = Font.system(size: 13)
    /// Button labels.
    static let buttonFont = Font.system(size: 13, weight: .medium)
    /// Placeholder text in the miniature chat field.
    static let miniFieldFont = Font.system(size: 12)

    /// Motion for the miniature Dock opening its gap.
    static let open = Animation.spring(response: 0.7, dampingFraction: 0.76)
    /// Motion for steps changing state.
    static let settle = Animation.snappy(duration: 0.25)
}
