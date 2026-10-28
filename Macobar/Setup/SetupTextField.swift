import SwiftUI

/// A labelled text field in the setup palette: graphite well, hairline rim that brightens on focus.
struct SetupTextField: View {
    /// What the field is for, shown above it.
    let label: String
    /// The edited text.
    @Binding var text: String
    /// Hint shown while the field is empty.
    let prompt: String
    /// Whether typing is hidden, for keys.
    var isSecure = false
    /// Whether the field has keyboard focus.
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(SetupStyle.detailFont)
                .foregroundStyle(SetupStyle.ash)
            field
                .textFieldStyle(.plain)
                .font(SetupStyle.fieldFont)
                .focused($isFocused)
                .padding(.horizontal, 12)
                .frame(height: SetupStyle.fieldHeight)
                .background(SetupStyle.graphite, in: .rect(cornerRadius: SetupStyle.fieldCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: SetupStyle.fieldCornerRadius, style: .continuous)
                        .strokeBorder(isFocused ? SetupStyle.cream.opacity(0.45) : SetupStyle.smoke, lineWidth: 1)
                }
                .animation(SetupStyle.settle, value: isFocused)
        }
    }

    /// A secure or plain field with the prompt in the quiet text colour.
    @ViewBuilder private var field: some View {
        let hint = Text(prompt).foregroundStyle(SetupStyle.ash.opacity(0.7))
        if isSecure {
            SecureField(label, text: $text, prompt: hint)
        } else {
            TextField(label, text: $text, prompt: hint)
                .autocorrectionDisabled()
        }
    }
}
