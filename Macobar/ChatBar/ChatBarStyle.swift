import SwiftUI

/// Design tokens for the chat field and reply sheet.
enum ChatBarStyle {
    /// Width the Dock gap is sized for.
    static let preferredFieldWidth: CGFloat = 320
    /// Tallest the field capsule gets, roughly one Dock icon.
    static let maxFieldHeight: CGFloat = 34
    /// Space kept between the field capsule and the Dock's top and bottom edges.
    static let fieldVerticalMargin: CGFloat = 6
    /// Space kept between the field capsule and the neighbouring Dock icons.
    static let fieldHorizontalMargin: CGFloat = 3

    /// Width of the reply sheet.
    static let replyWidth: CGFloat = 420
    /// Tallest the reply text gets before it scrolls.
    static let maxReplyHeight: CGFloat = 280
    /// Corner radius of the reply sheet.
    static let replyCornerRadius: CGFloat = 20
    /// Gap between the Dock's top edge and the reply sheet.
    static let replyLift: CGFloat = 8

    /// Text typed into the field.
    static let fieldFont = Font.system(size: 13)
    /// The prompt echoed at the top of the reply sheet.
    static let promptFont = Font.system(size: 12, weight: .medium)
    /// The reply itself.
    static let replyFont = Font.system(size: 13)
    /// Extra leading that keeps multi-line replies easy to read.
    static let replyLineSpacing: CGFloat = 3

    /// Fill of the recessed field well at rest.
    static let wellOpacity = 0.06
    /// Fill of the field well while typing.
    static let activeWellOpacity = 0.10
    /// Hairline around the field well at rest.
    static let hairlineOpacity = 0.12

    /// Motion for the reply sheet rising out of the Dock.
    static let rise = Animation.spring(response: 0.42, dampingFraction: 0.82)
    /// Motion for small state changes inside the field.
    static let settle = Animation.snappy(duration: 0.18)
}
