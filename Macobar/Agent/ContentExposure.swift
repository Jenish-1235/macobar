/// What outside text has reached the model, which decides when Always Allow stops counting and when sending data off the Mac asks.
struct ContentExposure: Equatable, Sendable {
    /// A tool brought in outside text (a web page, file, screen, email, remote server) that could carry instructions.
    var hasOutsideContent = false
    /// Some of that text may hold the user's private data: anything but a public web page fetched without asking.
    var hasPrivateContent = false

    /// Everything this exposure or `other` has seen.
    func combined(with other: ContentExposure) -> ContentExposure {
        ContentExposure(
            hasOutsideContent: hasOutsideContent || other.hasOutsideContent,
            hasPrivateContent: hasPrivateContent || other.hasPrivateContent
        )
    }

    /// This exposure after a tool that `readsOutsideContent` ran; only a data-sending tool that ran without asking (a public page fetch) brings in text that can't be private.
    func adding(readsOutsideContent: Bool, sendsDataOut: Bool, risk: ToolRisk) -> ContentExposure {
        guard readsOutsideContent else { return self }
        let isPublic = sendsDataOut && risk == .none
        return ContentExposure(hasOutsideContent: true, hasPrivateContent: hasPrivateContent || !isPublic)
    }

    /// Whether a call with `risk` may run without asking: Always Allow stops counting once outside text has come in, and a tool that sends data off the Mac asks once private text could leak through it.
    func runsWithoutAsking(risk: ToolRisk, isAlwaysAllowed: Bool, sendsDataOut: Bool) -> Bool {
        switch risk {
        case .none: !(sendsDataOut && hasPrivateContent)
        case .confirmOnce: isAlwaysAllowed && !hasOutsideContent
        case .confirmEveryTime: false
        }
    }
}
