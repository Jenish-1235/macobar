import Synchronization

/// The tools the user chose Always Allow for, by MCP session: the choice lasts until that app reconnects and never carries over to another app or to Macie.
final class MCPSessionGrants: Sendable {
    /// Most sessions remembered; the oldest is forgotten first, so its app is simply asked again.
    private static let maxSessions = 64

    /// A tool always allowed at the risk the user saw, so allowing a harmless use (reading the clipboard) never covers a riskier one (writing it).
    private struct Grant: Hashable {
        /// The tool's name.
        let toolName: String
        /// The risk of the call the user chose Always Allow for.
        let risk: ToolRisk
    }

    /// Session IDs and the tools always allowed in each, oldest first.
    private let sessions = Mutex<[(id: String, grants: Set<Grant>)]>([])

    /// Whether the user always allows `toolName` at `risk` in `sessionID`.
    func isGranted(_ toolName: String, at risk: ToolRisk, in sessionID: String) -> Bool {
        let grant = Grant(toolName: toolName, risk: risk)
        return sessions.withLock { sessions in sessions.first { $0.id == sessionID }?.grants.contains(grant) == true }
    }

    /// Stops asking before `toolName` runs at `risk` in `sessionID`.
    func grant(_ toolName: String, at risk: ToolRisk, in sessionID: String) {
        sessions.withLock { sessions in
            let earlier = sessions.first { $0.id == sessionID }?.grants ?? []
            sessions.removeAll { $0.id == sessionID }
            sessions.append((sessionID, earlier.union([Grant(toolName: toolName, risk: risk)])))
            if sessions.count > Self.maxSessions { sessions.removeFirst() }
        }
    }
}
