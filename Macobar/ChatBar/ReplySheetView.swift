import SwiftUI

/// The glass sheet that rises out of the Dock to show the prompt and its reply.
struct ReplySheetView: View {
    /// Shared chat state.
    let model: ChatBarModel
    /// Reports the sheet's natural size so its panel can wrap it exactly.
    let onSizeChange: (CGSize) -> Void

    var body: some View {
        ZStack {
            if let exchange = model.exchange {
                sheet(for: exchange)
                    .transition(.offset(y: 14).combined(with: .opacity).combined(with: .scale(scale: 0.97, anchor: .bottom)))
            }
        }
        .fixedSize()
        .onGeometryChange(for: CGSize.self, of: \.size, action: onSizeChange)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(ChatBarStyle.rise, value: model.exchange == nil)
    }

    /// The card for one prompt and its reply.
    private func sheet(for exchange: ChatBarModel.Exchange) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(exchange.prompt)
                .font(ChatBarStyle.promptFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            ScrollView {
                Text(replyText(for: exchange))
                    .font(ChatBarStyle.replyFont)
                    .lineSpacing(ChatBarStyle.replyLineSpacing)
                    .foregroundStyle(exchange.failureMessage == nil ? .primary : .secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: ChatBarStyle.maxReplyHeight)
        }
        .padding(18)
        .frame(width: ChatBarStyle.replyWidth, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: ChatBarStyle.replyCornerRadius))
    }

    /// The text to show: the failure if there is one, otherwise the reply so far.
    private func replyText(for exchange: ChatBarModel.Exchange) -> String {
        exchange.failureMessage ?? exchange.reply
    }
}
