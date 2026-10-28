import SwiftUI

/// Macie's cursor dot: rises from the Dock to its point, then pulses there.
struct PointerDot: View {
    /// Where the dot comes to rest, in view coordinates.
    let target: CGPoint
    /// Where the dot sets off from: the bottom centre of the screen, near the Dock.
    let start: CGPoint
    /// Seconds to wait before setting off, so it follows marks drawn before it.
    let delay: Double
    /// Users who prefer reduced motion get the dot in place, without travel or pulse.
    @Environment(\.accessibilityReduceMotion) private var prefersReducedMotion
    /// Whether the dot has reached its target.
    @State private var hasArrived = false
    /// Whether the pulse ring is expanding.
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(OverlayStyle.ink, lineWidth: 2)
                .scaleEffect(isPulsing ? OverlayStyle.pulseScale : 1)
                .opacity(isPulsing ? 0 : 0.8)
            Circle()
                .fill(OverlayStyle.ink)
                .overlay(Circle().strokeBorder(OverlayStyle.outline, lineWidth: 2))
                .shadow(color: OverlayStyle.ink.opacity(0.6), radius: OverlayStyle.glowRadius)
        }
        .frame(width: OverlayStyle.pointerSize, height: OverlayStyle.pointerSize)
        .position(hasArrived || prefersReducedMotion ? target : start)
        .opacity(hasArrived || prefersReducedMotion ? 1 : 0)
        .onAppear(perform: arrive)
    }

    /// Travels to the target, then starts pulsing.
    private func arrive() {
        guard !prefersReducedMotion else { return }
        withAnimation(OverlayStyle.travel.delay(delay)) {
            hasArrived = true
        } completion: {
            withAnimation(OverlayStyle.pulse) { isPulsing = true }
        }
    }
}
