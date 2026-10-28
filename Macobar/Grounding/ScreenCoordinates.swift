import CoreGraphics

/// Conversions between the coordinate spaces grounding works in. "Screen points" are global points with a top-left
/// origin on the main screen, as Accessibility, SCWindow and CGWindowList report them.
enum ScreenCoordinates {
    /// The location a mouse CGEvent needs to land on `point`: events use the same top-left global space, so it is unchanged.
    static func eventLocation(for point: CGPoint) -> CGPoint {
        point
    }

    /// `point` in AppKit's global space (bottom-left origin), given the main screen's height.
    static func appKitPoint(for point: CGPoint, mainScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: mainScreenHeight - point.y)
    }

    /// A Vision bounding box (normalized to the image, bottom-left origin) in screen points, for an image showing `area`.
    static func screenRect(forNormalized box: CGRect, in area: CGRect) -> CGRect {
        CGRect(x: area.minX + box.minX * area.width, y: area.minY + (1 - box.maxY) * area.height,
               width: box.width * area.width, height: box.height * area.height)
    }

    /// `rect` in screen points as pixels of an image of `area` drawn at `imageSize`, with CoreGraphics' bottom-left origin.
    static func imageRect(for rect: CGRect, in area: CGRect, imageSize: CGSize) -> CGRect {
        let scaleX = imageSize.width / area.width
        let scaleY = imageSize.height / area.height
        return CGRect(x: (rect.minX - area.minX) * scaleX, y: imageSize.height - (rect.maxY - area.minY) * scaleY,
                      width: rect.width * scaleX, height: rect.height * scaleY)
    }
}
