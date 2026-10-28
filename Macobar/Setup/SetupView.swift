import SwiftUI

/// The one-screen setup: headline, the miniature Dock, three steps and a finish button.
struct SetupView: View {
    /// Setup state and actions.
    let model: SetupModel
    /// Opens the Connect screen for step 3.
    let onConnectModel: () -> Void
    /// Closes setup once everything is done.
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
            Text("Your Mac, one sentence away.")
                .font(SetupStyle.displayFont)
                .tracking(-0.9)
                .padding(.top, 44)
            Text("Meet Macie, the agent in your Dock. Three steps and it's ready.")
                .font(SetupStyle.ledeFont)
                .foregroundStyle(SetupStyle.ash)
                .padding(.top, 12)
            MiniDockView(isFieldInDock: model.isInDock)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 44)
            steps
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, SetupStyle.margin)
        .padding(.top, 60)
        .padding(.bottom, 40)
        .frame(width: SetupStyle.windowSize.width, height: SetupStyle.windowSize.height, alignment: .topLeading)
        .background(SetupStyle.charcoal)
        .foregroundStyle(SetupStyle.cream)
        .tint(SetupStyle.cream)
    }

    /// Macie and the lowercase wordmark.
    private var brand: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Macie(mood: macieMood, size: 20)
            Text("macobar")
                .font(SetupStyle.wordmarkFont)
        }
    }

    /// Macie asks while waiting on System Settings and smiles once setup is done.
    private var macieMood: Macie.Mood {
        if model.isFinished { return .done }
        return model.isWaitingForAccessibility ? .asking : .resting
    }

    /// The three numbered steps, separated by hairlines.
    private var steps: some View {
        VStack(spacing: 0) {
            SetupStepRow(
                number: 1,
                title: "Allow Accessibility",
                detail: model.isWaitingForAccessibility
                    ? "Turn on macobar in Privacy & Security → Accessibility."
                    : "Lets Macie find the Dock and work in your apps.",
                status: model.isAccessibilityGranted ? .done : .current,
                actionTitle: model.isWaitingForAccessibility ? "Open Settings" : "Allow access",
                doneTitle: "Allowed",
                action: allowAccessibility
            )
            hairline
            SetupStepRow(
                number: 2,
                title: "Add to the Dock",
                detail: "Makes room after Finder. The Dock restarts once.",
                status: model.isInDock ? .done : (model.isAccessibilityGranted ? .current : .upcoming),
                actionTitle: "Add to Dock",
                doneTitle: "Added",
                action: model.addToDock
            )
            hairline
            SetupStepRow(
                number: 3,
                title: "Connect a model",
                detail: "Pick the provider Macie thinks with. Your key stays in your Keychain.",
                status: model.connectedProvider != nil ? .done : (model.isInDock ? .current : .upcoming),
                actionTitle: "Connect",
                doneTitle: model.connectedProvider?.displayName ?? "",
                action: onConnectModel
            )
        }
    }

    /// The divider between steps.
    private var hairline: some View {
        Rectangle()
            .fill(SetupStyle.smoke)
            .frame(height: 1)
    }

    /// A closing line and the finish button, live once both steps are done.
    private var footer: some View {
        HStack {
            Text(model.isFinished ? "Click the field in your Dock whenever you need it." : " ")
                .font(SetupStyle.detailFont)
                .foregroundStyle(SetupStyle.ash)
            Spacer()
            Button("Start using macobar", action: onFinish)
                .buttonStyle(SetupButtonStyle(isProminent: model.isFinished))
                .keyboardShortcut(model.isFinished ? .defaultAction : .none)
                .disabled(!model.isFinished)
                .opacity(model.isFinished ? 1 : 0.38)
        }
        .animation(SetupStyle.settle, value: model.isFinished)
    }

    /// Requests access, then brings setup back to the front once it's granted.
    private func allowAccessibility() {
        Task {
            guard await model.allowAccessibility() else { return }
            NSApp.activate()
        }
    }
}
