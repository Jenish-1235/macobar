import Foundation

/// Decides, from the prompt alone, whether the fast or the main model should take it.
enum PromptRouter {
    /// Prompts longer than this many words go to the main model.
    private static let longPromptWords = 40
    /// Commands up to this many words go to the fast model.
    private static let shortCommandWords = 12
    /// Anything else up to this many words goes to the fast model.
    private static let shortRequestWords = 6
    /// Leading words that don't change what's asked, e.g. "please" or "can you".
    private static let fillers: Set = ["please", "hey", "hi", "ok", "okay", "macie", "can", "could", "would", "will", "you"]
    /// First words of a quick action on the Mac.
    private static let commandVerbs: Set = [
        "open", "close", "quit", "launch", "play", "pause", "resume", "skip", "mute", "unmute", "volume",
        "timer", "remind", "arrange", "switch", "hide", "show", "turn", "lock", "set", "start", "stop",
    ]
    /// Words that ask for writing, research or reasoning.
    private static let reasoningWords: Set = [
        "plan", "research", "write", "draft", "compose", "analyse", "analyze", "analysis", "compare", "summarise",
        "summarize", "summary", "explain", "debug", "code", "script", "refactor", "review", "essay", "report",
        "translate", "investigate", "why",
    ]
    /// Words that start a question.
    private static let questionWords: Set = ["how", "why", "what", "what's", "which", "who", "when", "where", "should"]
    /// Words that point back to the previous answer.
    private static let backReferences: Set = ["it", "that", "this", "them", "those", "these", "again", "same", "also"]
    /// Phrases asking for extra care.
    private static let carePhrases = ["think hard", "think carefully", "carefully", "step by step", "think it through", "take your time"]
    /// Phrases joining several steps.
    private static let stepPhrases = ["then", "after that", "once that's done", "followed by"]
    /// Phrases that need Macie to look at the screen or an image.
    private static let visionPhrases = ["on my screen", "on the screen", "on screen", "screenshot", "look at", "do you see", "can you see", "this image", "this photo", "this picture"]

    /// The model for `prompt`; `continuing` is the model that answered the remembered conversation, if any.
    static func route(_ prompt: String, continuing: ModelTier? = nil) -> Route {
        let words = words(in: prompt)
        let phrase = " " + words.joined(separator: " ") + " "
        let asks = words.drop { fillers.contains($0) }
        if contains(carePhrases, in: phrase) { return Route(tier: .strong, reason: "Asked to think carefully") }
        if words.count > longPromptWords { return Route(tier: .strong, reason: "Long prompt") }
        if contains(stepPhrases, in: phrase) || listItemCount(in: prompt) > 1 { return Route(tier: .strong, reason: "Several steps") }
        if contains(visionPhrases, in: phrase) { return Route(tier: .strong, reason: "Needs to see the screen") }
        if prompt.contains("```") { return Route(tier: .strong, reason: "Includes code") }
        if continuing == .strong && words.contains(where: backReferences.contains) { return Route(tier: .strong, reason: "Follows up on the main model") }
        if isCommand(asks) && words.count <= shortCommandWords { return Route(tier: .fast, reason: "Short command") }
        if words.contains(where: reasoningWords.contains) { return Route(tier: .strong, reason: "Needs writing or reasoning") }
        if prompt.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?") || asks.first.map(questionWords.contains) == true {
            return Route(tier: .strong, reason: "Question that needs reasoning")
        }
        if !words.isEmpty && words.count <= shortRequestWords { return Route(tier: .fast, reason: "Short request") }
        return Route(tier: .strong, reason: "Not clearly simple")
    }

    /// Whether `prompt` opens with a quick action, so a reply without any tool call means it wasn't done.
    static func looksLikeCommand(_ prompt: String) -> Bool {
        isCommand(words(in: prompt).drop { fillers.contains($0) })
    }

    /// Whether `words` start with a command verb.
    private static func isCommand(_ words: ArraySlice<String>) -> Bool {
        words.first.map(commandVerbs.contains) == true
    }

    /// `prompt` lowercased and split into words, keeping apostrophes.
    private static func words(in prompt: String) -> [String] {
        prompt.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .split { !($0.isLetter || $0.isNumber || $0 == "'") }
            .map(String.init)
    }

    /// Whether any of `phrases` appears as whole words in `padded`, which is space-joined words with a space at each end.
    private static func contains(_ phrases: [String], in padded: String) -> Bool {
        phrases.contains { padded.contains(" \($0) ") }
    }

    /// Lines of `prompt` that start a bulleted or numbered list item.
    private static func listItemCount(in prompt: String) -> Int {
        prompt.split(separator: "\n").count { line in
            let start = line.drop { $0 == " " }
            let isBullet = ["- ", "* ", "• "].contains { start.hasPrefix($0) }
            let isNumbered = start.first?.isNumber == true && start.drop { $0.isNumber }.hasPrefix(".")
            return isBullet || isNumbered
        }
    }
}
