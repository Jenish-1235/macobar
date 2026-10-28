import CoreGraphics

/// Converts points between the coordinate spaces a drawing passes through on its way to a screen.
enum OverlayCoordinates {
    /// `point` given with a top-left origin on the main screen (as Accessibility reports it), in AppKit's bottom-left-origin global space.
    static func appKitPoint(fromTopLeft point: CGPoint, mainScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: mainScreenHeight - point.y)
    }

    /// `point` in AppKit global space, measured from the top-left corner of the screen at `screenFrame` (a view's space).
    static func viewPoint(fromAppKit point: CGPoint, in screenFrame: CGRect) -> CGPoint {
        CGPoint(x: point.x - screenFrame.minX, y: screenFrame.maxY - point.y)
    }
}
