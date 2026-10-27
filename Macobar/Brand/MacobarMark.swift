import SwiftUI

/// macobar's mark: the agent (a dot) resting on the Dock (a line); the dot bounces like a launching app while the agent works.
struct MacobarMark: View {
    /// Whether the agent is working, which makes the dot bounce.
    let isWorking: Bool
    /// Whether the mark is in use, which brings it to full strength.
    let isActive: Bool
    /// Multiplier for every dimension, so the mark stays crisp at any size.
    var scale: CGFloat = 1
    /// Users who prefer reduced motion get a still, accent-coloured dot instead of a bounce.
    @Environment(\.accessibilityReduceMotion) private var prefersReducedMotion

    /// Time for one hop, close to the Dock's own launch bounce.
    private static let hopDuration = 0.55
    /// How high the dot hops at scale 1.
    private static let hopHeight: CGFloat = 4.5

    var body: some View {
        TimelineView(.animation(paused: !isBouncing)) { timeline in
            VStack(spacing: 0.5 * scale) {
                Circle()
                    .fill(isWorking ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .frame(width: 5.5 * scale, height: 5.5 * scale)
                    .offset(y: -hopOffset(at: timeline.date))
                Capsule()
                    .fill(.primary)
                    .frame(width: 15 * scale, height: 1.5 * scale)
            }
            .opacity(isActive || isWorking ? 0.9 : 0.45)
        }
        .frame(width: 16 * scale, height: 18 * scale)
        .accessibilityHidden(true)
    }

    /// Whether the bounce should be animating right now.
    private var isBouncing: Bool { isWorking && !prefersReducedMotion }

    /// Height of the dot at `date`: repeated hops that land softly on the line.
    private func hopOffset(at date: Date) -> CGFloat {
        guard isBouncing else { return 0 }
        let phase = date.timeIntervalSinceReferenceDate / Self.hopDuration * .pi
        return Self.hopHeight * scale * abs(sin(phase))
    }
}
