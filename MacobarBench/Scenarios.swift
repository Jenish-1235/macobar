/// The tasks every model is measured on.
extension Scenario {
    /// Every scenario, from one obvious tool call to multi-step and risky tasks.
    static let all: [Scenario] = [
        Scenario("open-app", prompt: "Open Safari", outputs: ["open_app": "Opened Safari."],
                 expects: .calls([ExpectedCall("open_app", .contains("name", "Safari"))])),
        Scenario("plain-question", prompt: "What does RAM stand for?",
                 expects: .noTools),
        Scenario("timer", prompt: "Set a timer for 5 minutes", outputs: ["set_timer": "Timer set; it goes off at 14:35."],
                 expects: .calls([ExpectedCall("set_timer", .number("minutes", 5))])),
        Scenario("read-front-window", prompt: "Summarize the window I'm looking at",
                 outputs: [
                     "get_frontmost_context": "App: Pages (com.apple.iWork.Pages)\nWindow: Q3 Planning.pages\nFocused element: AXTextArea",
                     "read_window_text": """
                         Window: Q3 Planning.pages

                         Q3 Planning
                         Goals: ship the Dock chat field, cut onboarding to one screen, reach 1,000 daily users.
                         Risks: people skip the Accessibility step; local models are slow on older Macs.
                         """,
                 ],
                 expects: .calls([ExpectedCall("get_frontmost_context"), ExpectedCall("read_window_text")])),
        Scenario("this-page", prompt: "Summarize this page",
                 outputs: [
                     "get_frontmost_context": "App: Safari (com.apple.Safari)\nWindow: Migrating to Swift 6",
                     "get_browser_tab": "Browser: Safari\nTitle: Migrating to Swift 6\nURL: https://www.swift.org/migration/",
                     "read_page": """
                         Title: Migrating to Swift 6
                         URL: https://www.swift.org/migration/
                         Migrating to Swift 6. Swift 6 turns data-race warnings into errors. Migrate one module at a time: \
                         turn on complete checking, fix the warnings, then switch the language mode.
                         """,
                 ],
                 expects: .calls([ExpectedCall("read_page")])),
        Scenario("snap-window", prompt: "Snap Safari to the left half of the screen",
                 expects: .calls([ExpectedCall("arrange_window", .contains("app", "Safari"), .equals("position", "left_half"))])),
        Scenario("find-and-read", prompt: "When does my lease end? It's somewhere in my Documents.",
                 outputs: [
                     "search_documents": "Nothing is indexed yet, so there's nothing to search. Use search_files to find files by name or content.",
                     "index_documents": "Indexing started: 0 of 1,240 files done. Use search_files in the meantime.",
                     "search_files": "/Users/me/Documents/Home/Lease Agreement 2026.pdf\n/Users/me/Documents/Home/Moving Checklist.pdf",
                     "read_file": "RESIDENTIAL LEASE AGREEMENT\nTerm: 1 September 2026 to 31 August 2027.\nRent: $2,150 per month.",
                 ],
                 expects: .calls([ExpectedCall("search_files"), ExpectedCall("read_file", .contains("path", "Lease Agreement"))])),
        Scenario("open-website", prompt: "Open apple.com",
                 expects: .calls([ExpectedCall("open_url", .contains("url", "apple.com"))])),
        Scenario("volume", prompt: "Turn the volume down to 30%",
                 expects: .calls([ExpectedCall("system_control", .equals("action", "set_volume"), .number("level", 30))])),
        Scenario("reminder", prompt: "Remind me to call the dentist on Friday at 9am",
                 expects: .calls([ExpectedCall("create_reminder", .contains("title", "dentist"), .contains("due", "09:00"))])),
        Scenario("agenda", prompt: "What's on my calendar today?",
                 outputs: ["list_events": "09:30–10:00 Standup\n13:00–14:00 Lunch with Sam\n16:00–16:30 Design review"],
                 expects: .calls([ExpectedCall("list_events")])),
        Scenario("play-music", prompt: "Play some Radiohead",
                 outputs: ["music": "Playing “Weird Fishes/Arpeggi” by Radiohead."],
                 expects: .calls([ExpectedCall("music", .equals("action", "play_search"), .contains("query", "Radiohead"))])),
        Scenario("text-contact", prompt: "Text Mom that I'll be 10 minutes late",
                 outputs: ["find_contact": "Mom\n  phone mobile: +1 (555) 010-0123", "send_message": "Sent."],
                 expects: .calls([
                     ExpectedCall("find_contact", .contains("name", "Mom")),
                     ExpectedCall("send_message", .contains("to", "555"), .contains("text", "late")),
                 ])),
        Scenario("trash-file", prompt: "Delete old-notes.txt from my Desktop",
                 outputs: ["search_files": "/Users/me/Desktop/old-notes.txt", "manage_file": "Moved old-notes.txt to the Trash."],
                 expects: .calls([ExpectedCall("manage_file", .equals("action", "trash"), .contains("path", "old-notes.txt"))])),
        Scenario("quit-app", prompt: "Quit Music", outputs: ["control_app": "Quit Music."],
                 expects: .calls([ExpectedCall("control_app", .contains("name", "Music"), .equals("action", "quit"))])),
        Scenario("remember-fact", prompt: "Remember that I prefer metric units", outputs: ["remember": "Remembered as m1."],
                 expects: .calls([ExpectedCall("remember", .contains("fact", "metric"))])),
        Scenario("diagram", prompt: "Draw me a diagram of how a pull request gets reviewed and merged",
                 outputs: ["show_diagram": "Showing the diagram in a 820 × 400 point window."],
                 expects: .calls([ExpectedCall("show_diagram")])),
    ]
}
