import SwiftUI

/// Macie, the agent who lives in macobar: a soft pebble sitting on the Dock line whose face shows what it's doing.
/// Drawn in the current foreground style, with eyes cut out so whatever is behind shows through.
struct Macie: View {
    /// What Macie is doing, which sets its face and motion.
    enum Mood: Equatable, Sendable {
        /// Idle in the Dock; blinks now and then.
        case resting
        /// Reading what the user types.
        case listening
        /// Carrying out a request; hops like a launching app.
        case working
        /// Finished the request.
        case done
        /// Waiting for the user's OK.
        case asking
        /// Something went wrong.
        case stuck
    }

    /// Current mood.
    let mood: Mood
    /// Body width in points; every other dimension scales from it.
    var size: CGFloat = 12
    /// Whether to draw the Dock line Macie sits on.
    var showsGround = true
    /// Users who prefer reduced motion get no hop and no blink.
    @Environment(\.accessibilityReduceMotion) private var prefersReducedMotion
    /// Whether the eyes are mid-blink.
    @State private var isBlinking = false

    /// Time for one hop, close to the Dock's own launch bounce.
    private static let hopDuration = 0.55
    /// Hop height as a fraction of body width.
    private static let hopHeight = 0.2

    var body: some View {
        TimelineView(.animation(paused: !isHopping)) { timeline in
            VStack(spacing: size * 0.03) {
                pebble(lift: lift(at: timeline.date))
                if showsGround {
                    Capsule().frame(width: size * 1.7, height: max(1.5, size * 0.045))
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: mood)
        .task(id: mood) { await blinkWhileResting() }
        .accessibilityHidden(true)
    }

    /// The body with its face cut out, squashed, tilted and lifted for the current mood.
    private func pebble(lift: CGFloat) -> some View {
        let scale = bodyScale(lift: lift)
        return ZStack {
            RoundedRectangle(cornerRadius: bodyHeight / 2, style: .continuous)
            face
                .offset(y: faceOffset)
                .blendMode(.destinationOut)
        }
        .frame(width: size, height: bodyHeight)
        .scaleEffect(x: scale.width, y: scale.height, anchor: .bottom)
        .drawingGroup() // Flattens body and face into one layer so the eye cut-outs work in live windows.
        .rotationEffect(.degrees(mood == .asking ? -9 : 0), anchor: .bottom)
        .offset(y: -lift)
    }

    /// The eyes (and smile) for the current mood.
    @ViewBuilder private var face: some View {
        switch mood {
        case .resting:
            HStack(spacing: size * 0.2) { eye(0.085, isBlinking ? 0.013 : 0.13); eye(0.085, isBlinking ? 0.013 : 0.13) }
        case .listening:
            HStack(spacing: size * 0.2) { eye(0.095, 0.17); eye(0.095, 0.17) }
        case .working:
            HStack(spacing: size * 0.18) { eye(0.1, 0.065); eye(0.1, 0.065) }
        case .done:
            VStack(spacing: bodyHeight * 0.08) {
                HStack(spacing: size * 0.18) { happyEye; happyEye }
                MacieArc(bulgesUp: false)
                    .stroke(style: StrokeStyle(lineWidth: size * 0.035, lineCap: .round))
                    .frame(width: size * 0.12, height: bodyHeight * 0.04)
            }
        case .asking:
            HStack(spacing: size * 0.2) { eye(0.08, 0.12); eye(0.105, 0.18) }
        case .stuck:
            HStack(spacing: size * 0.2) { eye(0.13, 0.04); eye(0.13, 0.04) }
        }
    }

    /// An oval eye, sized as fractions of the body width.
    private func eye(_ width: CGFloat, _ height: CGFloat) -> some View {
        Capsule().frame(width: size * width, height: size * height)
    }

    /// A closed, smiling eye: a small upward arc.
    private var happyEye: some View {
        MacieArc(bulgesUp: true)
            .stroke(style: StrokeStyle(lineWidth: size * 0.042, lineCap: .round))
            .frame(width: size * 0.105, height: bodyHeight * 0.075)
    }

    /// Body height; Macie is a little wider than tall.
    private var bodyHeight: CGFloat { size * 0.82 }

    /// How far the face sits from the centre: up when listening, down when stuck.
    private var faceOffset: CGFloat {
        switch mood {
        case .listening: -bodyHeight * 0.1
        case .stuck: bodyHeight * 0.06
        default: -bodyHeight * 0.02
        }
    }

    /// Whether the hop should be animating right now.
    private var isHopping: Bool { mood == .working && !prefersReducedMotion }

    /// Height above the ground at `date`: repeated hops that land softly.
    private func lift(at date: Date) -> CGFloat {
        guard isHopping else { return 0 }
        let phase = date.timeIntervalSinceReferenceDate / Self.hopDuration * .pi
        return size * Self.hopHeight * abs(sin(phase))
    }

    /// Body stretch per mood; while hopping, squashed near the ground and stretched in the air.
    private func bodyScale(lift: CGFloat) -> CGSize {
        switch mood {
        case .listening:
            return CGSize(width: 0.96, height: 1.06)
        case .stuck:
            return CGSize(width: 1.07, height: 0.88)
        case .working where isHopping:
            let squash = max(0, 1 - lift / (size * Self.hopHeight) * 4)
            return CGSize(width: 0.95 + 0.1 * squash, height: 1.06 - 0.13 * squash)
        default:
            return CGSize(width: 1, height: 1)
        }
    }

    /// Blinks every few seconds while resting, until the mood changes.
    private func blinkWhileResting() async {
        guard mood == .resting, !prefersReducedMotion else { return }
        do {
            while true {
                try await Task.sleep(for: .seconds(Double.random(in: 3...6)))
                withAnimation(.easeIn(duration: 0.06)) { isBlinking = true }
                try await Task.sleep(for: .milliseconds(120))
                withAnimation(.easeOut(duration: 0.08)) { isBlinking = false }
            }
        } catch {
            isBlinking = false // Cancelled because the mood changed: open the eyes.
        }
    }
}

/// A shallow arc, bulging up for happy eyes and down for the smile.
private struct MacieArc: Shape {
    /// Whether the arc's middle rises above its ends.
    let bulgesUp: Bool

    /// Traces the arc across the rect.
    func path(in rect: CGRect) -> Path {
        let endY = bulgesUp ? rect.maxY : rect.minY
        let controlY = bulgesUp ? rect.minY - rect.height : rect.maxY + rect.height
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: endY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: endY), control: CGPoint(x: rect.midX, y: controlY))
        return path
    }
}
