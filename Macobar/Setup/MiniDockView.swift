import SwiftUI

/// A monochrome miniature of the Dock that opens a gap after Finder and slides the chat field in.
struct MiniDockView: View {
    /// Whether the chat field has been added to the real Dock.
    let isFieldInDock: Bool
    /// Users who prefer reduced motion get a cross-fade instead of the spring.
    @Environment(\.accessibilityReduceMotion) private var prefersReducedMotion

    /// Side of each miniature app icon.
    private static let iconSize: CGFloat = 36
    /// Number of outlined app icons after the gap.
    private static let appIconCount = 5
    /// Width of the miniature chat field once it's in.
    private static let fieldWidth: CGFloat = 214

    var body: some View {
        HStack(spacing: 8) {
            appIcon(isFinder: true)
            if isFieldInDock {
                miniField
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.3, anchor: .leading).combined(with: .opacity),
                        removal: .opacity
                    ))
            } else {
                insertionCaret
            }
            ForEach(0..<Self.appIconCount, id: \.self) { _ in
                appIcon(isFinder: false)
            }
            Rectangle()
                .fill(SetupStyle.smoke)
                .frame(width: 1, height: Self.iconSize - 10)
                .padding(.horizontal, 2)
            appIcon(isFinder: false)
        }
        .padding(12)
        .background(SetupStyle.graphite, in: .rect(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(SetupStyle.cream.opacity(0.09), lineWidth: 1)
        }
        .animation(prefersReducedMotion ? .easeInOut(duration: 0.2) : SetupStyle.open, value: isFieldInDock)
        .accessibilityElement()
        .accessibilityLabel(isFieldInDock ? "The Dock with macobar's field after Finder" : "The Dock before macobar is added")
    }

    /// An app icon: solid cream for Finder, outlined for everything else.
    private func appIcon(isFinder: Bool) -> some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(isFinder ? SetupStyle.cream.opacity(0.92) : Color.clear)
            .strokeBorder(SetupStyle.cream.opacity(isFinder ? 0 : 0.22), lineWidth: 1)
            .frame(width: Self.iconSize, height: Self.iconSize)
    }

    /// A thin cream caret marking where the field will go.
    private var insertionCaret: some View {
        Capsule()
            .fill(SetupStyle.cream.opacity(0.5))
            .frame(width: 2, height: Self.iconSize - 14)
    }

    /// The chat field in miniature: the mark and its placeholder in a recessed capsule.
    private var miniField: some View {
        HStack(spacing: 8) {
            MacobarMark(isWorking: false, isActive: true)
            Text("Tell your Mac what to do")
                .font(SetupStyle.miniFieldFont)
                .foregroundStyle(SetupStyle.ash)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(width: Self.fieldWidth, height: Self.iconSize - 4)
        .background(SetupStyle.cream.opacity(0.05), in: Capsule())
        .overlay(Capsule().strokeBorder(SetupStyle.cream.opacity(0.2), lineWidth: 0.75))
    }
}
