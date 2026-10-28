import Testing

/// Verifies that approval requests resume the waiting agent exactly once.
struct ApprovalRequestTests {
    @Test("A decision made while waiting resumes the waiter")
    func decideWhileWaiting() async {
        let request = ApprovalRequest(action: "Quit Safari", canAlwaysAllow: true)
        async let decision = request.decision()
        try? await Task.sleep(for: .milliseconds(20))
        request.decide(.alwaysAllow)
        #expect(await decision == .alwaysAllow)
    }

    @Test("A decision made before waiting is returned at once, and later answers are ignored")
    func decideBeforeWaiting() async {
        let request = ApprovalRequest(action: "Run a shell command", canAlwaysAllow: false)
        request.decide(.deny)
        request.decide(.allow)
        #expect(await request.decision() == .deny)
    }
}
