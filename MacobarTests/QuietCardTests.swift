import Testing

/// Verifies that the reply card stays hidden while Macie works and rises only when she needs the user.
@MainActor
struct QuietCardTests {
    /// Gives queued work up to two seconds to make `condition` true.
    private func waitUntil(_ condition: () -> Bool) async {
        var attempts = 0
        while !condition(), attempts < 1_000 {
            attempts += 1
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    @Test("Work in progress shows only in the field; an approval and the finished reply show in the card")
    func cardRisesOnlyWhenNeeded() async {
        let responder = HeldResponder()
        let model = ChatBarModel(responder: responder)
        model.draft = "Quit Safari"
        model.submit()
        #expect(model.shownExchange == nil)
        #expect(model.workingStatus == "Thinking…")

        responder.send(.activity("Quitting Safari"))
        await waitUntil { model.workingStatus == "Quitting Safari…" }
        #expect(model.workingStatus == "Quitting Safari…")
        #expect(model.shownExchange == nil)

        responder.send(.approval(ApprovalRequest(action: "Quitting Safari", canAlwaysAllow: true)))
        await waitUntil { model.shownExchange != nil }
        #expect(model.shownExchange?.pendingApproval != nil)
        #expect(model.workingStatus == nil)

        model.decide(.allow)
        #expect(model.shownExchange == nil)

        responder.send(.text("Safari is closed."))
        responder.finish()
        await waitUntil { model.shownExchange != nil }
        #expect(model.shownExchange?.reply == "Safari is closed.")
        #expect(model.workingStatus == nil)
    }
}
