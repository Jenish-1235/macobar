import SwiftUI

/// One provider in the Connect grid; the selected one is rimmed in cream with a check.
struct ProviderTile: View {
    /// The provider shown.
    let kind: ProviderKind
    /// Whether it's the chosen provider.
    let isSelected: Bool
    /// Chooses this provider.
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(kind.displayName)
                    .font(SetupStyle.stepTitleFont)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: SetupStyle.fieldHeight)
            .background(isSelected ? SetupStyle.graphite : Color.clear, in: .rect(cornerRadius: SetupStyle.fieldCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SetupStyle.fieldCornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? SetupStyle.cream.opacity(0.6) : SetupStyle.smoke, lineWidth: 1)
            }
            .foregroundStyle(isSelected ? SetupStyle.cream : SetupStyle.cream.opacity(0.78))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(SetupStyle.settle, value: isSelected)
    }
}
