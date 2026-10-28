import SwiftUI

/// The History screen: what Macie did, newest first and grouped by day, with Undo on file changes.
struct HistoryView: View {
    /// The entries, undo and clear.
    let model: HistoryModel
    /// Closes the window.
    let onDone: () -> Void

    /// Height of the scrolling list, fixed so the window keeps its size as entries come and go.
    private static let listHeight: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                Macie(mood: model.failure == nil ? .resting : .stuck, size: 20)
                Text("macobar")
                    .font(SetupStyle.wordmarkFont)
            }
            Text("What Macie did.")
                .font(SetupStyle.titleFont)
                .tracking(-0.5)
                .padding(.top, 36)
            Text("Every action, newest first. File changes can be undone; they go back where they were or to the Trash.")
                .font(SetupStyle.ledeFont)
                .foregroundStyle(SetupStyle.ash)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            list
                .frame(height: Self.listHeight)
                .padding(.top, 26)
            footer
                .padding(.top, 24)
        }
        .padding(.horizontal, SetupStyle.sheetMargin)
        .padding(.top, 48)
        .padding(.bottom, 36)
        .frame(width: SetupStyle.connectWidth, alignment: .topLeading)
        .background(SetupStyle.charcoal)
        .foregroundStyle(SetupStyle.cream)
        .tint(SetupStyle.cream)
    }

    /// The days and their entries, or a line saying there are none yet.
    @ViewBuilder private var list: some View {
        if model.days.isEmpty {
            Text("Nothing yet. Actions Macie takes show up here.")
                .font(SetupStyle.detailFont)
                .foregroundStyle(SetupStyle.ash)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.days) { day in
                        Text(Self.title(for: day.date))
                            .font(SetupStyle.stepTitleFont)
                            .foregroundStyle(SetupStyle.ash)
                            .padding(.top, 18)
                            .padding(.bottom, 6)
                        ForEach(day.entries) { entry in
                            HistoryRow(entry: entry, onUndo: { model.undo(entry) })
                            Rectangle()
                                .fill(SetupStyle.smoke)
                                .frame(height: 1)
                        }
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    /// Why something failed, Clear History, and Done.
    private var footer: some View {
        HStack(spacing: 10) {
            if let failure = model.failure {
                Label(failure, systemImage: "exclamationmark.circle")
                    .font(SetupStyle.detailFont)
                    .foregroundStyle(SetupStyle.cream.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            Button("Clear History", action: model.clear)
                .buttonStyle(SetupButtonStyle(isProminent: false))
                .disabled(!canClear)
                .opacity(canClear ? 1 : 0.38)
            Button("Done", action: onDone)
                .buttonStyle(SetupButtonStyle(isProminent: true))
                .keyboardShortcut(.defaultAction)
        }
    }

    /// Whether there's anything to clear: entries, or a log that can't be read and needs starting over.
    private var canClear: Bool { !model.days.isEmpty || model.failure != nil }

    /// "Today", "Yesterday", or the date written out, e.g. "Monday, 26 October".
    private static func title(for day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

/// One entry: its time, what Macie did, how it ended, and Undo while it can be undone.
private struct HistoryRow: View {
    /// The action shown.
    let entry: ActivityEntry
    /// Reverses the action.
    let onUndo: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(entry.date, format: .dateTime.hour().minute())
                .font(SetupStyle.detailFont.monospacedDigit())
                .foregroundStyle(SetupStyle.ash)
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.activity)
                    .font(SetupStyle.fieldFont)
                    .lineLimit(2)
                Text(outcome)
                    .font(SetupStyle.detailFont)
                    .foregroundStyle(SetupStyle.ash)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if entry.isUndoable {
                Button("Undo", action: onUndo)
                    .buttonStyle(SetupButtonStyle(isProminent: false))
            }
        }
        .padding(.vertical, 10)
    }

    /// How the action ended, in a few words.
    private var outcome: String {
        if entry.isUndone { return "Undone" }
        switch entry.outcome {
        case .succeeded: return "Done"
        case .failed: return entry.result.isEmpty ? "Failed" : "Failed: \(entry.result)"
        case .declined: return "You declined"
        }
    }
}
