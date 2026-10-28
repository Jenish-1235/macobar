import Foundation

/// Writes an email in Mail, leaving it open as a draft or sending it.
struct ComposeEmailTool: Tool {
    /// Name the model calls it by.
    let name = "compose_email"
    /// When to use it and what it returns.
    let description = """
        Writes an email in Mail, opened as a draft by default; set send only when the user clearly asked to send it \
        now. Recipients must be addresses; use find_contact to look one up.
        """

    /// The recipients, subject, body and whether to send.
    var parameters: JSONValue {
        Schema.object([
            "to": Schema.strings("Email addresses."),
            "subject": Schema.string("Subject."),
            "body": Schema.string("Plain-text body."),
            "cc": Schema.strings("Cc addresses."),
            "send": Schema.boolean("Send now instead of drafting. Defaults to false."),
        ], required: ["to", "subject", "body"])
    }

    /// Sending asks every time; drafting doesn't.
    func risk(for input: ToolInput) -> ToolRisk {
        input.bool("send") ? .confirmEveryTime : .none
    }

    /// Describes the email and who it's for.
    func activity(for input: ToolInput) -> String {
        "\(input.bool("send") ? "Sending" : "Drafting") an email to \(input.strings("to").joined(separator: ", "))"
    }

    /// Creates the message in Mail and sends it or brings Mail forward with the draft.
    func run(_ input: ToolInput) async throws -> String {
        let recipients = input.strings("to")
        guard !recipients.isEmpty else { throw ToolError("\"to\" must list at least one email address.") }
        let subject = try input.requiredString("subject")
        let shouldSend = input.bool("send")
        let script = """
            on run argv
                set messageSubject to item 1 of argv
                set messageBody to item 2 of argv
                set shouldSend to (item 3 of argv) is "true"
                set toCount to (item 4 of argv) as integer
                tell application "Mail"
                    set newMessage to make new outgoing message with properties {subject:messageSubject, content:messageBody, visible:true}
                    tell newMessage
                        repeat with argumentIndex from 5 to (4 + toCount)
                            make new to recipient at end of to recipients with properties {address:item argumentIndex of argv}
                        end repeat
                        repeat with argumentIndex from (5 + toCount) to (count of argv)
                            make new cc recipient at end of cc recipients with properties {address:item argumentIndex of argv}
                        end repeat
                    end tell
                    if shouldSend then
                        send newMessage
                    else
                        activate
                    end if
                end tell
            end run
            """
        let arguments = [subject, input.rawString("body") ?? "", String(shouldSend), String(recipients.count)] + recipients + input.strings("cc")
        _ = try await AppleScript.run(script, arguments: arguments)
        let recipientList = recipients.joined(separator: ", ")
        return shouldSend
            ? "Sent “\(subject)” to \(recipientList)."
            : "Opened a draft of “\(subject)” to \(recipientList) in Mail for the user to review and send."
    }
}

/// Sends an iMessage through Messages.
struct SendMessageTool: Tool {
    /// Name the model calls it by.
    let name = "send_message"
    /// When to use it and what it returns.
    let description = """
        Sends an iMessage. "to" must be a phone number or email; for a named person, call find_contact first.
        """

    /// The recipient and message text.
    var parameters: JSONValue {
        Schema.object([
            "to": Schema.string("Phone number (with country code if known) or iMessage email."),
            "text": Schema.string("Message text."),
        ], required: ["to", "text"])
    }

    /// Sending a message asks every time.
    func risk(for input: ToolInput) -> ToolRisk {
        .confirmEveryTime
    }

    /// Describes who the message is for.
    func activity(for input: ToolInput) -> String {
        "Sending a message to \(input.string("to") ?? "someone")"
    }

    /// Sends the text to the handle over iMessage.
    func run(_ input: ToolInput) async throws -> String {
        let handle = try input.requiredString("to")
        let isPhoneNumber = handle.contains(where: \.isNumber) && handle.allSatisfy { $0.isNumber || "+-() .".contains($0) }
        guard isPhoneNumber || handle.contains("@") else {
            throw ToolError("“\(handle)” isn't a phone number or email. Call find_contact to look up their number or email first.")
        }
        let script = """
            on run argv
                tell application "Messages"
                    set iMessageAccount to first account whose service type = iMessage
                    send (item 2 of argv) to participant (item 1 of argv) of iMessageAccount
                end tell
            end run
            """
        _ = try await AppleScript.run(script, arguments: [handle, try input.requiredString("text")])
        return "Sent the message to \(handle)."
    }
}

/// Creates and searches notes in Notes.
struct NotesTool: Tool {
    /// Name the model calls it by.
    let name = "notes"
    /// When to use it and what it returns.
    let description = "Creates a note in the user's Notes, or searches note titles and text (up to 20 matches)."

    /// The action and its title, body or query.
    var parameters: JSONValue {
        Schema.object([
            "action": Schema.oneOf(["create", "search"], "What to do."),
            "title": Schema.string("Title (create)."),
            "body": Schema.string("Plain-text body (create)."),
            "query": Schema.string("Text to find (search)."),
        ], required: ["action"])
    }

    /// Creating asks once; searching doesn't.
    func risk(for input: ToolInput) -> ToolRisk {
        input.string("action") == "create" ? .confirmOnce : .none
    }

    /// Reading brings outside text the model will read, so later risky actions always ask.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        input.string("action") == "search"
    }

    /// Describes the note being created or searched for.
    func activity(for input: ToolInput) -> String {
        input.string("action") == "create"
            ? "Creating the note “\(input.string("title") ?? "")”"
            : "Searching notes for “\(input.string("query") ?? "")”"
    }

    /// Runs the requested action.
    func run(_ input: ToolInput) async throws -> String {
        switch try input.requiredString("action") {
        case "create": try await create(title: input.requiredString("title"), body: input.rawString("body") ?? "")
        case "search": try await search(for: input.requiredString("query"))
        case let action: throw ToolError("Unknown action “\(action)”. Use create or search.")
        }
    }

    /// Saves a note in the default folder of the default account, with `title` as its heading.
    private func create(title: String, body: String) async throws -> String {
        let script = """
            on run argv
                tell application "Notes"
                    make new note at default folder of default account with properties {body:(item 1 of argv)}
                end tell
            end run
            """
        let bodyLines = body.components(separatedBy: .newlines).map(htmlEscaped)
        let html = "<h1>\(htmlEscaped(title))</h1>" + bodyLines.joined(separator: "<br>")
        _ = try await AppleScript.run(script, arguments: [html])
        return "Created the note “\(title)” in Notes."
    }

    /// Up to 20 notes whose title or text contains `query`, with dates and a preview.
    private func search(for query: String) async throws -> String {
        let script = """
            on run argv
                set searchText to item 1 of argv
                set results to {}
                tell application "Notes"
                    repeat with matchedNote in (notes whose name contains searchText or plaintext contains searchText)
                        if (count of results) is 20 then exit repeat
                        set preview to plaintext of matchedNote
                        if length of preview > 200 then set preview to text 1 thru 200 of preview
                        set end of results to (name of matchedNote) & (character id 31) & ((modification date of matchedNote) as string) & (character id 31) & preview
                    end repeat
                end tell
                set AppleScript's text item delimiters to character id 30
                return results as string
            end run
            """
        let output = try await AppleScript.run(script, arguments: [query])
        guard !output.isEmpty else { return "No notes contain “\(query)”." }
        return output.split(separator: "\u{1E}").map { record in
            let fields = record.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
            let preview = fields.dropFirst(2).joined().split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return "• \(fields[0]) (modified \(fields.count > 1 ? fields[1] : "unknown"))\n  \(preview)"
        }.joined(separator: "\n")
    }

    /// `text` with HTML's special characters escaped.
    private func htmlEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
