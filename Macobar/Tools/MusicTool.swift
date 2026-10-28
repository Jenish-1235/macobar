import Foundation

/// Controls playback in the Music app.
struct MusicTool: Tool {
    /// Name the model calls it by.
    let name = "music"
    /// When to use it and what it returns.
    let description = """
        Controls Music playback or reports what's playing. play_search plays the first match in the user's library \
        only, not the Apple Music catalog.
        """

    /// The playback action and, for play_search, what to look for.
    var parameters: JSONValue {
        Schema.object([
            "action": Schema.oneOf(["play", "pause", "next", "previous", "now_playing", "play_search"], "What to do."),
            "query": Schema.string("Song, artist or album (play_search)."),
        ], required: ["action"])
    }

    /// Track names come from file tags others wrote, so reporting them brings in outside text.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        input.string("action") == "now_playing" || input.string("action") == "play_search"
    }

    /// Describes the playback change.
    func activity(for input: ToolInput) -> String {
        switch input.string("action") {
        case "pause": "Pausing music"
        case "next": "Skipping to the next track"
        case "previous": "Going back a track"
        case "now_playing": "Checking what's playing"
        case "play_search": "Playing “\(input.string("query") ?? "")”"
        default: "Playing music"
        }
    }

    /// Runs the action in Music.
    func run(_ input: ToolInput) async throws -> String {
        switch try input.requiredString("action") {
        case "play":
            _ = try await AppleScript.run(#"tell application "Music" to play"#)
            return "Playing."
        case "pause":
            _ = try await AppleScript.run(#"tell application "Music" to pause"#)
            return "Paused."
        case "next":
            _ = try await AppleScript.run(#"tell application "Music" to next track"#)
            return "Skipped to the next track."
        case "previous":
            _ = try await AppleScript.run(#"tell application "Music" to previous track"#)
            return "Went back to the previous track."
        case "now_playing":
            return try await nowPlaying()
        case "play_search":
            return try await playFirstMatch(for: input.requiredString("query"))
        case let action:
            throw ToolError("Unknown action “\(action)”. Use play, pause, next, previous, now_playing or play_search.")
        }
    }

    /// The current track, artist, album and player state.
    private func nowPlaying() async throws -> String {
        let script = """
            tell application "Music"
                if player state is stopped then return "Nothing is playing."
                set playingTrack to current track
                return (name of playingTrack) & " by " & (artist of playingTrack) & " from " & (album of playingTrack) & " (" & (player state as string) & ")"
            end tell
            """
        return try await AppleScript.run(script)
    }

    /// Plays the first library track matching `query` and says which it was.
    private func playFirstMatch(for query: String) async throws -> String {
        let script = """
            on run argv
                tell application "Music"
                    set matches to search library playlist 1 for (item 1 of argv)
                    if matches is {} then return ""
                    set firstMatch to item 1 of matches
                    play firstMatch
                    return (name of firstMatch) & " by " & (artist of firstMatch)
                end tell
            end run
            """
        let played = try await AppleScript.run(script, arguments: [query])
        guard !played.isEmpty else { throw ToolError("No songs in the user's Music library match “\(query)”.") }
        return "Playing \(played)."
    }
}
