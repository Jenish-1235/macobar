import Foundation
import Synchronization

/// The names AI apps gave when they connected, by MCP session, so an approval in the Dock can say which app is asking.
final class MCPClientNames: Sendable {
    /// Most sessions remembered; the oldest is forgotten first.
    private static let maxSessions = 64
    /// Longest name shown in the Dock, in Unicode scalars so stacked combining marks can't make one character huge.
    private static let maxNameLength = 40
    /// Readable names for the IDs the apps in the Share Tools window send.
    private static let knownApps = ["claude-code": "Claude Code", "claude-ai": "Claude Desktop", "codex-mcp-client": "Codex"]
    /// Words no app may put in its name, so a request can't pass itself off as Macie's own.
    private static let reservedWords = ["macie", "macobar"]

    /// Session IDs and their app's name, oldest first.
    private let sessions = Mutex<[(id: String, name: String)]>([])

    /// Remembers the app that opened `sessionID`, preferring its display `title` to its `name`; a name posing as Macie, even with lookalike letters, is ignored.
    func record(name: String?, title: String?, for sessionID: String) {
        let given = title ?? name.map { Self.knownApps[$0] ?? $0 } ?? ""
        let firstLine = given.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let shown = String(String.UnicodeScalarView(Self.visible(firstLine).unicodeScalars.prefix(Self.maxNameLength)))
            .trimmingCharacters(in: .whitespaces)
        let lettersOnly = Self.plainLetters(shown)
        guard !shown.isEmpty, !Self.reservedWords.contains(where: lettersOnly.contains) else { return }
        sessions.withLock { sessions in
            sessions.removeAll { $0.id == sessionID }
            sessions.append((sessionID, shown))
            if sessions.count > Self.maxSessions { sessions.removeFirst() }
        }
    }

    /// `text` with line breaks and control characters as spaces and invisible formatting characters (such as right-to-left overrides) removed.
    static func visible(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .format: continue
            case .control, .lineSeparator, .paragraphSeparator: scalars.append(" ")
            default: scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    /// `text` as lowercase plain Latin letters only, so lookalikes such as "Мacie" (Cyrillic М), "Ｍａｃｉｅ" or "M a c i e" still read "macie".
    private static func plainLetters(_ text: String) -> String {
        let latin = text.applyingTransform(.toLatin, reverse: false) ?? text
        let folded = latin.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return String(String.UnicodeScalarView(folded.unicodeScalars.filter(CharacterSet.letters.contains)))
    }

    /// The name of the app that opened `sessionID`, if it gave one.
    func name(for sessionID: String) -> String? {
        sessions.withLock { sessions in sessions.first { $0.id == sessionID }?.name }
    }
}
