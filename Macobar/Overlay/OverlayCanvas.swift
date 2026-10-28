import SwiftUI

/// One screen's share of the current drawing: each shape moved into this screen's coordinates.
struct OverlayCanvas: View {
    /// The drawing every screen shows.
    let board: OverlayBoard
    /// This screen's frame in AppKit global coordinates.
    let screenFrame: CGRect

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let drawing = board.drawing {
                    ZStack {
                        ForEach(Array(drawing.shapes.enumerated()), id: \.offset) { index, shape in
                            OverlayMarkView(
                                shape: shape.mapped { OverlayCoordinates.viewPoint(fromAppKit: $0, in: screenFrame) },
                                canvasSize: proxy.size,
                                delay: Double(index) * OverlayStyle.stagger
                            )
                        }
                    }
                    .id(drawing.id)
                    .transition(.opacity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
