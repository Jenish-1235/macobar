import Foundation
import Testing

/// Verifies which model takes a prompt, when the fast model hands over, and that the fast account is saved.
struct RoutingTests {
    @Test("Short commands go to the fast model", arguments: [
        "open Safari",
        "Quit Spotify",
        "set a timer for 10 minutes",
        "volume 30",
        "play some jazz",
        "remind me to call Mum at 5pm",
        "please switch to Xcode",
        "arrange my windows side by side",
        "can you close Finder?",
        "open VS Code",
    ])
    func commandsAreFast(prompt: String) {
        #expect(PromptRouter.route(prompt) == Route(tier: .fast, reason: "Short command"))
    }

    @Test("A short request that isn't a question goes to the fast model")
    func shortRequestIsFast() {
        #expect(PromptRouter.route("dark mode on") == Route(tier: .fast, reason: "Short request"))
    }

    @Test("Hard prompts go to the main model, with the reason", arguments: [
        ("open Safari and then search for flights to Tokyo", "Several steps"),
        ("Do these:\n- empty the trash\n- mute the Mac", "Several steps"),
        ("write an email to Sam about the launch", "Needs writing or reasoning"),
        ("compare the M4 and M5 MacBook Air", "Needs writing or reasoning"),
        ("plan my week", "Needs writing or reasoning"),
        ("why is my Mac slow?", "Needs writing or reasoning"),
        ("what's the best way to back up my photos?", "Question that needs reasoning"),
        ("think carefully about how to rename these files", "Asked to think carefully"),
        ("what's on my screen?", "Needs to see the screen"),
        ("take a screenshot", "Needs to see the screen"),
        ("fix this ```let x = 1```", "Includes code"),
        ("tidy up the files sitting in my downloads folder from last month", "Not clearly simple"),
    ])
    func hardPromptsAreStrong(prompt: String, reason: String) {
        #expect(PromptRouter.route(prompt) == Route(tier: .strong, reason: reason))
    }

    @Test("A prompt over 40 words goes to the main model even if it starts with a command")
    func longPromptIsStrong() {
        let prompt = "open " + Array(repeating: "word", count: 41).joined(separator: " ")
        #expect(PromptRouter.route(prompt) == Route(tier: .strong, reason: "Long prompt"))
    }

    @Test("A follow-up stays with the main model when it answered last")
    func followUpStaysStrong() {
        #expect(PromptRouter.route("close it", continuing: .strong).tier == .strong)
        #expect(PromptRouter.route("close it", continuing: .fast).tier == .fast)
        #expect(PromptRouter.route("close it").tier == .fast)
    }

    @Test("Commands are recognised after filler words, other prompts are not")
    func looksLikeCommand() {
        #expect(PromptRouter.looksLikeCommand("Hey Macie, could you open Mail"))
        #expect(!PromptRouter.looksLikeCommand("what time is it"))
    }

    @Test("A clean run stands")
    func cleanRunStands() {
        let run = RunOutcome(toolCalls: 1, answer: "Opened Safari.", completedActions: ["Opening Safari"])
        #expect(Escalation.reason(toEscalate: run, expectedAction: true) == nil)
    }

    @Test("A plain answer to a non-command stands")
    func plainAnswerStands() {
        #expect(Escalation.reason(toEscalate: RunOutcome(answer: "It's 3 pm."), expectedAction: false) == nil)
    }

    @Test("One failed tool call with an answer stands")
    func oneErrorStands() {
        let run = RunOutcome(toolCalls: 1, toolErrors: 1, answer: "Spotify isn't installed.")
        #expect(Escalation.reason(toEscalate: run, expectedAction: true) == nil)
    }

    @Test("A run whose action the user turned down stands, so they aren't asked again")
    func declinedStands() {
        let run = RunOutcome(toolCalls: 1, userDeclined: true, answer: "OK, I won't send it.")
        #expect(Escalation.reason(toEscalate: run, expectedAction: true) == nil)
    }

    @Test("A run that didn't finish is handed over")
    func unfinishedEscalates() {
        #expect(Escalation.reason(toEscalate: RunOutcome(toolCalls: 30, didFinish: false), expectedAction: true) == "The fast model didn't finish")
    }

    @Test("Two failed tool calls are handed over")
    func toolErrorsEscalate() {
        let run = RunOutcome(toolCalls: 3, toolErrors: 2, answer: "Done.")
        #expect(Escalation.reason(toEscalate: run, expectedAction: true) == "2 tool calls failed")
    }

    @Test("A command answered without any tool call is handed over")
    func noActionEscalates() {
        let run = RunOutcome(answer: "Sure, Safari is now open.")
        #expect(Escalation.reason(toEscalate: run, expectedAction: true) == "It answered without acting")
    }

    @Test("An empty answer with no tool calls is handed over")
    func emptyAnswerEscalates() {
        #expect(Escalation.reason(toEscalate: RunOutcome(answer: " \n"), expectedAction: false) == "It gave no answer")
    }

    @Test("A refusal is handed over, whichever apostrophe it uses", arguments: [
        "I can't help with that.",
        "Sorry, I\u{2019}m unable to do this on your Mac.",
        "As an AI, I don't have access to your calendar.",
    ])
    func refusalEscalates(answer: String) {
        #expect(Escalation.reason(toEscalate: RunOutcome(answer: answer), expectedAction: false) == "It declined or gave up")
    }

    @Test("The handover prompt lists what was already done")
    func handoverListsActions() {
        let run = RunOutcome(toolCalls: 2, toolErrors: 2, completedActions: ["Opening Mail"])
        let prompt = Escalation.handoverPrompt(for: "email Sam", after: run)
        #expect(prompt.hasPrefix("email Sam\n\n"))
        #expect(prompt.contains("- Opening Mail"))
        #expect(Escalation.handoverPrompt(for: "email Sam", after: RunOutcome()) == "email Sam")
    }

    @Test("The fast account is saved, read back and cleared without touching the main one")
    func fastAccountRoundTrip() throws {
        let suite = "RoutingTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProviderAccountStore(defaults: defaults)
        let main = ProviderAccount(kind: .claude, model: "claude-opus-5-5")
        let fast = ProviderAccount(kind: .local, model: "qwen/qwen3.6-35b-a3b", setting: "http://localhost:1234/v1")
        #expect(store.fastAccount == nil)
        try store.activate(main)
        try store.setFastAccount(fast)
        #expect(store.fastAccount == fast)
        #expect(store.activeAccount == main)
        try store.setFastAccount(nil)
        #expect(store.fastAccount == nil)
        #expect(store.activeAccount == main)
    }
}
