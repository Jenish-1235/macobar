import SwiftUI

/// Pill buttons for setup: cream-filled for the next action, outlined otherwise.
struct SetupButtonStyle: ButtonStyle {
    /// Whether this is the one action the user should take next.
    let isProminent: Bool

    /// Draws the pill and a soft press response.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SetupStyle.buttonFont)
            .foregroundStyle(isProminent ? SetupStyle.ink : SetupStyle.cream)
            .padding(.horizontal, 18)
            .frame(height: 34)
            .background(Capsule().fill(isProminent ? SetupStyle.cream : Color.clear))
            .overlay(Capsule().strokeBorder(isProminent ? Color.clear : SetupStyle.smoke, lineWidth: 1))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(SetupStyle.settle, value: configuration.isPressed)
    }
}
