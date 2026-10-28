import SwiftUI

/// The Connections screen: the user's MCP servers with their status, and a form to add one.
struct ConnectionsView: View {
    /// The servers, their statuses and the form.
    @Bindable var model: ConnectionsModel
    /// Closes the window.
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                Macie(mood: model.testing.isEmpty ? .resting : .working, size: 20)
                Text("macobar")
                    .font(SetupStyle.wordmarkFont)
            }
            Text("Connect more tools.")
                .font(SetupStyle.titleFont)
                .tracking(-0.5)
                .padding(.top, 36)
            Text("Give Macie the tools of MCP servers, like GitHub, Linear or Notion. She asks before using them unless you trust the server.")
                .font(SetupStyle.ledeFont)
                .foregroundStyle(SetupStyle.ash)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            serverList
                .padding(.top, 30)
            form
                .padding(.top, 30)
            footer
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

    /// Each server as a row, or a line saying there are none.
    @ViewBuilder private var serverList: some View {
        if model.servers.isEmpty {
            Text("No servers yet.")
                .font(SetupStyle.detailFont)
                .foregroundStyle(SetupStyle.ash)
        } else {
            VStack(spacing: 0) {
                ForEach(model.servers) { server in
                    ServerRow(server: server, status: status(of: server.name), model: model)
                }
            }
            .overlay(alignment: .top) { Rectangle().fill(SetupStyle.smoke).frame(height: 1) }
        }
    }

    /// The new server's name, kind, command or address, and secrets.
    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add a server")
                .font(SetupStyle.stepTitleFont)
            HStack(alignment: .bottom, spacing: 10) {
                SetupTextField(label: "Name", text: $model.name, prompt: "github")
                Picker("Kind", selection: $model.kind) {
                    ForEach(ConnectionsModel.Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180, height: SetupStyle.fieldHeight)
            }
            SetupTextField(
                label: model.kind == .command ? "Command" : "Address",
                text: $model.target,
                prompt: model.kind == .command ? "npx -y @modelcontextprotocol/server-github" : "https://mcp.linear.app/mcp"
            )
            SecretLinesField(
                label: model.kind == .command ? "Environment variables (optional)" : "Headers (optional)",
                text: $model.secretLines
            )
        }
    }

    /// What went wrong, Add, and Done; whichever comes next is filled.
    private var footer: some View {
        HStack(spacing: 10) {
            if let problem = model.problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .font(SetupStyle.detailFont)
                    .foregroundStyle(SetupStyle.cream.opacity(0.85))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            Button("Add") {
                Task { await model.add() }
            }
            .buttonStyle(SetupButtonStyle(isProminent: model.canAdd))
            .disabled(!model.canAdd)
            .opacity(model.canAdd ? 1 : 0.38)
            Button("Done", action: onDone)
                .buttonStyle(SetupButtonStyle(isProminent: !model.canAdd))
                .keyboardShortcut(.cancelAction)
        }
    }

    /// The server's tool count, testing state, failure, or that it hasn't connected yet.
    private func status(of name: String) -> String {
        if model.testing.contains(name) { return "Connecting…" }
        switch model.statuses[name] {
        case .connected(let toolCount): return toolCount == 1 ? "1 tool" : "\(toolCount) tools"
        case .failed(let reason): return reason
        case nil: return "Not connected yet. Press Test to check it."
        }
    }
}

/// One server: its name, command or address, and status, with Trust, Test and Remove.
private struct ServerRow: View {
    /// The server shown.
    let server: MCPServerConfig
    /// Its status line.
    let status: String
    /// Carries out Trust, Test and Remove.
    let model: ConnectionsModel

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(server.name)
                    .font(SetupStyle.stepTitleFont)
                Text(target)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(SetupStyle.ash)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(status)
                    .font(SetupStyle.detailFont)
                    .foregroundStyle(SetupStyle.ash)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle("Trust", isOn: Binding(
                get: { server.isTrusted },
                set: { isTrusted in Task { await model.setTrusted(isTrusted, forServerNamed: server.name) } }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(SetupStyle.detailFont)
            .help("Run this server's tools without asking first")
            Button("Test") {
                Task { await model.test(server.name) }
            }
            .buttonStyle(SetupButtonStyle(isProminent: false))
            .disabled(model.testing.contains(server.name))
            Button("Remove") {
                Task { await model.remove(server.name) }
            }
            .buttonStyle(SetupButtonStyle(isProminent: false))
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(SetupStyle.smoke).frame(height: 1) }
    }

    /// The command line or address the server is reached by.
    private var target: String {
        switch server.transport {
        case .command(let executable, let arguments): ([executable] + arguments).joined(separator: " ")
        case .address(let url): url.absoluteString
        }
    }
}

/// A labelled multi-line field for "KEY=value" secrets, in the setup palette.
private struct SecretLinesField: View {
    /// What the lines are for, shown above the field.
    let label: String
    /// The edited lines.
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(SetupStyle.detailFont)
                .foregroundStyle(SetupStyle.ash)
            TextEditor(text: $text)
                .font(.system(size: 12.5, design: .monospaced))
                .scrollContentBackground(.hidden)
                .autocorrectionDisabled()
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .frame(height: 64)
                .background(SetupStyle.graphite, in: .rect(cornerRadius: SetupStyle.fieldCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: SetupStyle.fieldCornerRadius, style: .continuous)
                        .strokeBorder(SetupStyle.smoke, lineWidth: 1)
                }
            Text("One KEY=value per line, like GITHUB_TOKEN=… Kept in your Keychain.")
                .font(SetupStyle.detailFont)
                .foregroundStyle(SetupStyle.ash)
        }
    }
}
