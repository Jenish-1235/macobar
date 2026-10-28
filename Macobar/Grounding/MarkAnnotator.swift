import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Draws each mark's outline and numbered badge on a screenshot and encodes it for the model.
enum MarkAnnotator {
    /// Longest side sent, in pixels; bigger images cost more tokens without helping the model.
    private static let longestSide = 1280
    /// JPEG quality that keeps files small and text legible.
    private static let jpegQuality = 0.7
    /// Size of the numbers on the badges, in image pixels.
    private static let badgeFontSize: CGFloat = 12
    /// Space around a badge's number, in image pixels.
    private static let badgePadding: CGFloat = 3
    /// Width of each mark's outline, in image pixels.
    private static let outlineWidth: CGFloat = 1.5

    /// `image`, which shows `area` of the screen, scaled to fit `longestSide` with every mark outlined and numbered, as JPEG.
    static func annotatedJPEG(of image: CGImage, showing area: CGRect, marks: [ScreenMark]) throws -> ToolImage {
        let scale = min(1, Double(longestSide) / Double(max(image.width, image.height, 1)))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        let size = CGSize(width: width, height: height)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw ToolError("Couldn't prepare a \(width)×\(height) image.")
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        let rects = marks.map { ScreenCoordinates.imageRect(for: $0.target.frame, in: area, imageSize: size) }
        context.setStrokeColor(markColor)
        context.setLineWidth(outlineWidth)
        context.addRects(rects)
        context.strokePath()
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, badgeFontSize, nil) ?? CTFontCreateWithName("Helvetica-Bold" as CFString, badgeFontSize, nil)
        for (mark, rect) in zip(marks, rects) {
            drawBadge(mark.number, at: rect, font: font, in: context, imageSize: size)
        }
        guard let annotated = context.makeImage() else { throw ToolError("Couldn't prepare a \(width)×\(height) image.") }
        return try jpeg(from: annotated)
    }

    /// The colour of outlines and badges: a magenta that stands out on light and dark interfaces.
    private static var markColor: CGColor {
        CGColor(srgbRed: 1, green: 0.1, blue: 0.55, alpha: 1)
    }

    /// Draws `number` in white on a filled badge at the top-left corner of `rect`, kept inside the image.
    private static func drawBadge(_ number: Int, at rect: CGRect, font: CTFont, in context: CGContext, imageSize: CGSize) {
        let text = NSAttributedString(string: String(number), attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
        ])
        let line = CTLineCreateWithAttributedString(text)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let textWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        let badgeSize = CGSize(width: textWidth + 2 * badgePadding, height: ascent + descent + badgePadding)
        let origin = CGPoint(x: min(max(rect.minX, 0), imageSize.width - badgeSize.width),
                             y: min(max(rect.maxY - badgeSize.height, 0), imageSize.height - badgeSize.height))
        let badge = CGRect(origin: origin, size: badgeSize)
        context.setFillColor(markColor)
        context.addPath(CGPath(roundedRect: badge, cornerWidth: 3, cornerHeight: 3, transform: nil))
        context.fillPath()
        context.textPosition = CGPoint(x: badge.minX + badgePadding, y: badge.minY + badgePadding / 2 + descent)
        CTLineDraw(line, context)
    }

    /// `image` encoded as JPEG at `jpegQuality`.
    private static func jpeg(from image: CGImage) throws -> ToolImage {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ToolError("Couldn't encode the image as JPEG.")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ToolError("Couldn't encode the image as JPEG.") }
        return ToolImage(data: data as Data, mediaType: "image/jpeg")
    }
}
