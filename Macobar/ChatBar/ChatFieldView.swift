import SwiftUI

/// The text field pressed into the Dock gap.
struct ChatFieldView: View {
    /// Shared chat state.
    @Bindable var model: ChatBarModel
    /// Hands keyboard focus back to the app the user came from.
    let onLeave: () -> Void
    /// Runs the menu item the user picked.
    let onCommand: (ChatBarCommand) -> Void
    /// Whether the text field has keyboard focus.
    @FocusState private var isFocused: Bool
    /// Whether this panel is the key window, so focus styling clears when the user clicks away.
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        HStack(spacing: 8) {
            Macie(mood: macieMood, size: 13, showsGround: false)
                .frame(width: 18)
                .opacity(macieMood == .resting ? 0.7 : 1)
            TextField(model.workingStatus ?? "Tell your Mac what to do", text: $model.draft)
                .textFieldStyle(.plain)
                .font(ChatBarStyle.fieldFont)
                .focused($isFocused)
                .onSubmit(model.submit)
            if !model.draft.isEmpty {
                ReturnKeyHint()
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(well)
        .contentShape(Capsule())
        .onTapGesture { isFocused = true }
        .onExitCommand(perform: handleEscape)
        .onChange(of: model.fieldFocusRequests) { isFocused = true }
        .contextMenu {
            ForEach(ChatBarCommand.allCases.filter { $0 != .quit }, id: \.self) { command in
                Button(command.title) { onCommand(command) }
            }
            Toggle("Speak Replies", isOn: $model.speaksReplies)
            Divider()
            Button(ChatBarCommand.quit.title) { onCommand(.quit) }
        }
        .animation(ChatBarStyle.settle, value: model.draft.isEmpty)
        .animation(ChatBarStyle.settle, value: isActive)
    }

    /// Whether the field is focused in the key window.
    private var isActive: Bool { isFocused && activeState == .key }

    /// Macie's mood: listening while the user talks, asking while waiting for approval (hers or another app's), working while replying, listening while typing, then done or stuck.
    private var macieMood: Macie.Mood {
        if model.isHearingVoice { return .listening }
        if model.shownExternalApproval != nil { return .asking }
        guard let exchange = model.exchange else { return isActive ? .listening : .resting }
        if exchange.pendingApproval != nil { return .asking }
        if exchange.isResponding { return .working }
        if !model.draft.isEmpty { return .listening }
        return exchange.failureMessage == nil ? .done : .stuck
    }

    /// The recessed capsule the field sits in; its rim takes the accent colour while typing.
    private var well: some View {
        Capsule()
            .fill(.primary.opacity(isActive ? ChatBarStyle.activeWellOpacity : ChatBarStyle.wellOpacity))
            .overlay {
                Capsule().strokeBorder(
                    isActive ? AnyShapeStyle(.tint.opacity(0.6)) : AnyShapeStyle(.primary.opacity(ChatBarStyle.hairlineOpacity)),
                    lineWidth: isActive ? 1 : 0.5
                )
            }
    }

    /// First Escape clears the draft; the next one denies another app's waiting approval, or collapses the reply, and leaves the field.
    private func handleEscape() {
        guard model.draft.isEmpty else { return model.draft = "" }
        model.dismiss()
        isFocused = false
        onLeave()
    }
}

/// A small keycap showing that Return sends the prompt.
private struct ReturnKeyHint: View {
    var body: some View {
        Image(systemName: "return")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 18)
            .background(.primary.opacity(0.08), in: .rect(cornerRadius: 5))
            .accessibilityLabel("Press Return to send")
    }
}
