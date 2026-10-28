import AppKit
import SwiftUI

/// The Share Tools screen: a switch, then the address, token, Claude Code command and Claude Desktop config to copy.
struct ToolSharingView: View {
    /// Whether sharing is on, and the token.
    @Bindable var model: ToolSharingModel
    /// Closes the window.
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                Macie(mood: model.failure == nil ? .resting : .stuck, size: 20)
                Text("macobar")
                    .font(SetupStyle.wordmarkFont)
            }
            Text("Share Macie's tools.")
                .font(SetupStyle.titleFont)
                .tracking(-0.5)
                .padding(.top, 36)
            Text("Let AI apps you already use, like Claude Code, Codex or Claude Desktop, use Macie's tools on this Mac.")
                .font(SetupStyle.ledeFont)
                .foregroundStyle(SetupStyle.ash)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            sharingSwitch
                .padding(.top, 30)
            if let token = model.token {
                connectionDetails(token: token)
                    .padding(.top, 26)
            }
            Text("Shell and AppleScript are never shared. Anything that reads your data or changes your Mac asks for your OK in the Dock first.")
                .font(SetupStyle.detailFont)
                .foregroundStyle(SetupStyle.ash)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 22)
            HStack {
                Spacer()
                Button("Done", action: onDone)
                    .buttonStyle(SetupButtonStyle(isProminent: true))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 28)
        }
        .padding(.horizontal, SetupStyle.sheetMargin)
        .padding(.top, 48)
        .padding(.bottom, 36)
        .frame(width: SetupStyle.connectWidth, alignment: .topLeading)
        .background(SetupStyle.charcoal)
        .foregroundStyle(SetupStyle.cream)
        .tint(SetupStyle.cream)
    }

    /// The on/off switch with what it means right now.
    private var sharingSwitch: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Share with AI apps on this Mac", isOn: $model.isEnabled)
                .toggleStyle(.switch)
                .font(SetupStyle.stepTitleFont)
                .disabled(model.token == nil)
            Text(status)
                .font(SetupStyle.detailFont)
                .foregroundStyle(model.failure == nil ? SetupStyle.ash : SetupStyle.cream.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The failure, or whether apps can connect.
    private var status: String {
        if let failure = model.failure { return failure }
        return model.isEnabled ? "On. Only apps on this Mac that have the token can connect." : "Off. AI apps can't reach Macie."
    }

    /// The address, the token, the ready-made Claude Code command and Claude Desktop config, each with Copy.
    private func connectionDetails(token: String) -> some View {
        let hiddenToken = String(repeating: "•", count: 12) + token.suffix(4)
        return VStack(alignment: .leading, spacing: 18) {
            CopyableValue(label: "Address", shownText: MCPServer.address, copiedText: MCPServer.address)
            CopyableValue(label: "Token", shownText: hiddenToken, copiedText: token)
            CopyableValue(
                label: "Claude Code",
                shownText: ToolSharingModel.claudeCodeCommand(token: hiddenToken),
                copiedText: ToolSharingModel.claudeCodeCommand(token: token)
            )
            CopyableValue(
                label: "Claude Desktop (Settings → Developer → Edit Config)",
                shownText: ToolSharingModel.claudeDesktopConfig(token: hiddenToken),
                copiedText: ToolSharingModel.claudeDesktopConfig(token: token)
            )
        }
    }
}

/// A labelled read-only value in a graphite well, with a Copy button that puts `copiedText` on the clipboard.
private struct CopyableValue: View {
    /// The marker clipboard managers honour to leave a secret out of their history.
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    /// What the value is, shown above it.
    let label: String
    /// The value as shown, with any secret hidden.
    let shownText: String
    /// The value as copied, in full.
    let copiedText: String
    /// Whether the button briefly reads "Copied".
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(SetupStyle.detailFont)
                .foregroundStyle(SetupStyle.ash)
            HStack(spacing: 10) {
                Text(shownText)
                    .font(.system(size: 12.5, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .frame(height: SetupStyle.fieldHeight)
                    .background(SetupStyle.graphite, in: .rect(cornerRadius: SetupStyle.fieldCornerRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: SetupStyle.fieldCornerRadius, style: .continuous)
                            .strokeBorder(SetupStyle.smoke, lineWidth: 1)
                    }
                Button(action: copy) {
                    Text(didCopy ? "Copied" : "Copy")
                        .frame(width: 52)
                }
                .buttonStyle(SetupButtonStyle(isProminent: false))
            }
        }
    }

    /// Puts the full value on the clipboard, marked concealed when it holds a secret, and says so for a moment.
    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copiedText, forType: .string)
        if copiedText != shownText { NSPasteboard.general.setString("", forType: Self.concealedType) }
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            didCopy = false
        }
    }
}
