import SwiftUI

/// The Connect screen: pick a provider, paste a key, name the model, and check it in one go.
struct ConnectView: View {
    /// Form state and the connection check.
    @Bindable var model: ConnectModel
    /// Closes the screen without changing anything.
    let onCancel: () -> Void

    /// Two equal columns for the provider grid and the model row.
    private static let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                Macie(mood: macieMood, size: 20)
                Text("macobar")
                    .font(SetupStyle.wordmarkFont)
            }
            Text("Choose Macie's model.")
                .font(SetupStyle.titleFont)
                .tracking(-0.5)
                .padding(.top, 36)
            Text("Your key stays in your Keychain and is sent only to the provider you pick.")
                .font(SetupStyle.ledeFont)
                .foregroundStyle(SetupStyle.ash)
                .padding(.top, 10)
            providerGrid
                .padding(.top, 30)
            fields
                .padding(.top, 26)
            footer
                .padding(.top, 32)
        }
        .padding(.horizontal, SetupStyle.sheetMargin)
        .padding(.top, 48)
        .padding(.bottom, 36)
        .frame(width: SetupStyle.connectWidth, alignment: .topLeading)
        .background(SetupStyle.charcoal)
        .foregroundStyle(SetupStyle.cream)
        .tint(SetupStyle.cream)
        .disabled(model.status == .checking)
    }

    /// Macie works while checking, looks stuck on failure, and listens otherwise.
    private var macieMood: Macie.Mood {
        switch model.status {
        case .checking: .working
        case .failed: .stuck
        case .editing: .listening
        }
    }

    /// Every provider as a tile, two to a row.
    private var providerGrid: some View {
        LazyVGrid(columns: Self.columns, spacing: 10) {
            ForEach(ConnectModel.providers, id: \.self) { kind in
                ProviderTile(kind: kind, isSelected: model.kind == kind) { model.kind = kind }
            }
        }
    }

    /// The key, then the model beside the region or resource when the provider needs one.
    private var fields: some View {
        VStack(alignment: .leading, spacing: 18) {
            ZStack(alignment: .topTrailing) {
                SetupTextField(label: "API key", text: $model.apiKey, prompt: keyPrompt, isSecure: true)
                if let keyPage = model.kind.keyPageURL {
                    Link(destination: keyPage) {
                        Label("Get a key", systemImage: "arrow.up.right")
                            .labelStyle(TrailingIconLabelStyle())
                    }
                    .font(SetupStyle.detailFont)
                    .foregroundStyle(SetupStyle.ash)
                }
            }
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 10) {
                SetupTextField(label: model.kind == .azureOpenAI ? "Deployment" : "Model", text: $model.model, prompt: modelPrompt)
                if let setting = model.kind.requiredSetting {
                    SetupTextField(label: setting.label, text: $model.setting, prompt: settingPrompt(for: setting))
                }
            }
        }
    }

    /// Hint in the key field: whether a key is already saved.
    private var keyPrompt: String {
        model.hasSavedKey ? "Saved in your Keychain" : "Paste your \(model.kind.displayName) key"
    }

    /// Hint in the model field.
    private var modelPrompt: String {
        model.kind == .azureOpenAI ? "Your deployment name" : "Model ID"
    }

    /// An example value for the region or resource field.
    private func settingPrompt(for setting: ProviderSetting) -> String {
        switch setting {
        case .awsRegion: "us-east-1"
        case .azureResourceName: "my-resource"
        }
    }

    /// The check's progress or failure, Cancel, and Connect.
    private var footer: some View {
        HStack(spacing: 10) {
            statusLine
            Spacer(minLength: 16)
            Button("Cancel", action: onCancel)
                .buttonStyle(SetupButtonStyle(isProminent: false))
                .keyboardShortcut(.cancelAction)
            Button(model.status == .checking ? "Checking…" : "Connect") {
                Task { await model.connect() }
            }
            .buttonStyle(SetupButtonStyle(isProminent: true))
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canConnect)
            .opacity(model.canConnect || model.status == .checking ? 1 : 0.38)
        }
        .animation(SetupStyle.settle, value: model.status)
    }

    /// What's happening with the check, in the quiet text colour.
    @ViewBuilder private var statusLine: some View {
        switch model.status {
        case .editing:
            EmptyView()
        case .checking:
            Text("Asking \(model.kind.displayName) for a reply…")
                .font(SetupStyle.detailFont)
                .foregroundStyle(SetupStyle.ash)
        case .failed(let reason):
            Label(reason, systemImage: "exclamationmark.circle")
                .font(SetupStyle.detailFont)
                .foregroundStyle(SetupStyle.cream.opacity(0.85))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Puts a label's icon after its title, small, like an outbound link.
private struct TrailingIconLabelStyle: LabelStyle {
    /// Title, then a smaller icon.
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.title
            configuration.icon
                .imageScale(.small)
        }
    }
}
