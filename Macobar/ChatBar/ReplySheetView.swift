import SwiftUI

/// The glass sheet that rises out of the Dock only when Macie needs the user: an approval, her finished reply, or an action another app wants approved.
struct ReplySheetView: View {
    /// Shared chat state.
    let model: ChatBarModel
    /// Reports the sheet's natural size so its panel can wrap it exactly.
    let onSizeChange: (CGSize) -> Void

    var body: some View {
        ZStack {
            if let approval = model.shownExternalApproval {
                sheet(for: approval)
                    .transition(Self.rising)
            } else if let exchange = model.shownExchange {
                sheet(for: exchange)
                    .transition(Self.rising)
            }
        }
        .fixedSize()
        .onGeometryChange(for: CGSize.self, of: \.size, action: onSizeChange)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(ChatBarStyle.rise, value: model.shownExchange == nil)
        .animation(ChatBarStyle.rise, value: model.shownExternalApproval?.request)
    }

    /// How a card rises out of the Dock and sinks back.
    private static var rising: AnyTransition {
        .offset(y: 14).combined(with: .opacity).combined(with: .scale(scale: 0.97, anchor: .bottom))
    }

    /// The card for an action another app asked to run: who is asking, then Allow / Always Allow / Deny.
    private func sheet(for approval: ChatBarModel.ExternalApproval) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(approval.requester) wants to:")
                .font(ChatBarStyle.promptFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            ApprovalPrompt(request: approval.request, onDecide: approval.request.decide)
        }
        .replyCard()
    }

    /// The card for one prompt: actions, reply, and any approval waiting.
    private func sheet(for exchange: ChatBarModel.Exchange) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(exchange.prompt)
                .font(ChatBarStyle.promptFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            if !exchange.activities.isEmpty {
                ActivityList(activities: exchange.activities, isWorking: exchange.isResponding && exchange.pendingApproval == nil)
            }
            if !replyText(for: exchange).isEmpty {
                ScrollView {
                    Text(replyText(for: exchange))
                        .font(ChatBarStyle.replyFont)
                        .lineSpacing(ChatBarStyle.replyLineSpacing)
                        .foregroundStyle(exchange.failureMessage == nil ? .primary : .secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
                .defaultScrollAnchor(.bottom)
                .frame(maxHeight: ChatBarStyle.maxReplyHeight)
            }
            if let request = exchange.pendingApproval {
                ApprovalPrompt(request: request, onDecide: model.decide)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
        .replyCard()
        .animation(ChatBarStyle.settle, value: exchange.activities.count)
        .animation(ChatBarStyle.settle, value: exchange.pendingApproval)
    }

    /// The text to show: the failure if there is one, otherwise the reply so far.
    private func replyText(for exchange: ChatBarModel.Exchange) -> String {
        exchange.failureMessage.map { exchange.reply.isEmpty ? $0 : "\(exchange.reply)\n\n\($0)" } ?? exchange.reply
    }
}

extension View {
    /// Lays the content out as the reply card: padded, fixed width, on glass.
    fileprivate func replyCard() -> some View {
        padding(18)
            .frame(width: ChatBarStyle.replyWidth, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: ChatBarStyle.replyCornerRadius))
    }
}

/// The actions Macie has taken, newest last; the newest shows a spinner while she works on it.
private struct ActivityList: View {
    /// Actions in order.
    let activities: [String]
    /// Whether the newest action is still running.
    let isWorking: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(activities.suffix(ChatBarStyle.maxVisibleActivities).enumerated()), id: \.offset) { offset, activity in
                let isCurrent = isWorking && offset == min(activities.count, ChatBarStyle.maxVisibleActivities) - 1
                HStack(spacing: 7) {
                    Group {
                        if isCurrent {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold))
                        }
                    }
                    .frame(width: 12)
                    Text(activity)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(ChatBarStyle.activityFont)
                .foregroundStyle(isCurrent ? .primary : .secondary)
            }
        }
    }
}

/// Asks the user to allow an action, with Deny, Always Allow (when offered) and Allow.
private struct ApprovalPrompt: View {
    /// The action waiting.
    let request: ApprovalRequest
    /// Sends the user's answer.
    let onDecide: (ApprovalDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(request.action)
                    .font(ChatBarStyle.replyFont.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(request.reason ?? (request.canAlwaysAllow ? "Macie needs your OK first." : "Macie asks every time for this."))
                    .font(ChatBarStyle.activityFont)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button("Deny") { onDecide(.deny) }
                Spacer()
                if request.canAlwaysAllow {
                    Button("Always Allow") { onDecide(.alwaysAllow) }
                }
                Button("Allow") { onDecide(.allow) }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(.primary.opacity(0.05), in: .rect(cornerRadius: 12))
    }
}
