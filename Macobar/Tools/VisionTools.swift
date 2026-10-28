import AppKit
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers
import Vision

/// Shows the model a screenshot of an app's front window or the whole screen.
struct TakeScreenshotTool: VisualTool {
    /// Name the model calls it by.
    let name = "take_screenshot"
    /// When to call it and what it returns.
    let description = """
        Shows you a screenshot of an app's front window or the main screen. Use it when read_window_text and \
        read_screen_text aren't enough (charts, images, layout) or to check a UI action. Never captures macobar.
        """

    /// Takes the target and an optional app.
    var parameters: JSONValue { ScreenCapture.parameters }

    /// Seeing the screen can expose private data, so it asks first.
    func risk(for input: ToolInput) -> ToolRisk { .confirmOnce }

    /// Its result carries outside text the model will read, so later risky actions always ask.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        true
    }

    /// Names what is being captured.
    func activity(for input: ToolInput) -> String {
        "Taking a screenshot of \(ScreenCapture.subject(of: input))"
    }

    /// Captures the target and returns it scaled down as JPEG.
    func look(_ input: ToolInput) async throws -> (text: String, images: [ToolImage]) {
        let capture = try await ScreenCapture.image(for: input)
        return ("Screenshot of \(capture.subject).", [try ModelImage.jpeg(from: capture.image)])
    }
}

/// Reads the text on screen with OCR, for content Accessibility can't reach.
struct ReadScreenTextTool: Tool {
    /// Name the model calls it by.
    let name = "read_screen_text"
    /// When to call it and what it returns.
    let description = """
        OCRs an app's front window or the main screen, including images, PDFs, video and apps read_window_text can't \
        read. Prefer it over take_screenshot when only text matters. Never reads macobar.
        """

    /// Takes the target and an optional app.
    var parameters: JSONValue { ScreenCapture.parameters }

    /// Seeing the screen can expose private data, so it asks first.
    func risk(for input: ToolInput) -> ToolRisk { .confirmOnce }

    /// Its result carries outside text the model will read, so later risky actions always ask.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        true
    }

    /// Names what is being read.
    func activity(for input: ToolInput) -> String {
        "Reading the text on \(ScreenCapture.subject(of: input))"
    }

    /// Captures the target at full resolution and recognizes its text.
    func run(_ input: ToolInput) async throws -> String {
        let capture = try await ScreenCapture.image(for: input)
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let lines = try await request.perform(on: capture.image)
            .sorted { $0.topLeft.y > $1.topLeft.y }
            .map(\.transcript)
            .filter { !$0.isEmpty }
        return lines.isEmpty ? "No text found in \(capture.subject)." : "Text in \(capture.subject):\n\(lines.joined(separator: "\n"))"
    }
}

/// Shows the model an image or PDF file.
struct ViewImageTool: VisualTool {
    /// Name the model calls it by.
    let name = "view_image"
    /// When to call it and what it returns.
    let description = """
        Shows you an image file or a PDF's first page. Use search_files first if you don't know its path.
        """

    /// Takes the file's path.
    var parameters: JSONValue {
        Schema.object(["path": Schema.string("Full path; ~ allowed.")], required: ["path"])
    }

    /// Its result carries outside text the model will read, so later risky actions always ask.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        true
    }

    /// Names the file being viewed.
    func activity(for input: ToolInput) -> String {
        "Looking at “\(Self.fileURL(input.string("path") ?? "").lastPathComponent)”"
    }

    /// Loads the file, scaled down, and returns it as JPEG.
    func look(_ input: ToolInput) async throws -> (text: String, images: [ToolImage]) {
        let url = Self.fileURL(try input.requiredString("path"))
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ToolError("Nothing exists at \(url.path). Use search_files to find it.")
        }
        let image = url.pathExtension.lowercased() == "pdf" ? try Self.firstPage(ofPDFAt: url) : try Self.picture(at: url)
        return ("Image of \(url.lastPathComponent).", [try ModelImage.jpeg(from: image)])
    }

    /// The file URL for a model-given path, with a leading `~` expanded to the home folder.
    private static func fileURL(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    /// The image file at `url`, decoded no larger than the model needs and turned upright.
    private static func picture(at url: URL) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: ModelImage.longestSide,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ToolError("\(url.lastPathComponent) isn't an image macobar can read. Use PNG, JPEG, HEIC, GIF, TIFF, WebP or PDF.")
        }
        return image
    }

    /// The first page of the PDF at `url`, rendered upright with its long side at `ModelImage.longestSide`.
    private static func firstPage(ofPDFAt url: URL) throws -> CGImage {
        guard let document = CGPDFDocument(url as CFURL), document.isUnlocked, let page = document.page(at: 1) else {
            throw ToolError("\(url.lastPathComponent) isn't a readable PDF; it may be damaged or password-protected.")
        }
        let box = page.getBoxRect(.cropBox)
        let size = page.rotationAngle % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
        let scale = CGFloat(ModelImage.longestSide) / max(size.width, size.height, 1)
        return try ModelImage.render(width: Int(size.width * scale), height: Int(size.height * scale)) { context in
            context.scaleBy(x: scale, y: scale)
            context.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: size), rotate: 0, preserveAspectRatio: true))
            context.drawPDFPage(page)
        }
    }
}

/// Captures a window or display with ScreenCaptureKit, always leaving out macobar's own windows.
private enum ScreenCapture {
    /// What a screen tool can capture.
    enum Target: String, CaseIterable {
        /// One app's front window.
        case frontWindow = "front_window"
        /// The whole main display.
        case screen
    }

    /// Arguments the screen tools share: the target and an optional app.
    static var parameters: JSONValue {
        Schema.object([
            "target": Schema.oneOf(Target.allCases.map(\.rawValue), "Default front_window; screen is the whole main display."),
            "app": Schema.string("For front_window. Default: frontmost app."),
        ])
    }

    /// A short name for what `input` asks to capture, e.g. "Safari's window".
    static func subject(of input: ToolInput) -> String {
        guard input.string("target") != Target.screen.rawValue else { return "the screen" }
        return input.string("app").map { "\($0)'s window" } ?? "the front window"
    }

    /// The image `input` asks for at full resolution, and what it shows.
    static func image(for input: ToolInput) async throws -> (image: CGImage, subject: String) {
        let targetName = input.string("target") ?? Target.frontWindow.rawValue
        guard let target = Target(rawValue: targetName) else {
            throw ToolError("Unknown target \"\(targetName)\". Use one of: \(Target.allCases.map(\.rawValue).joined(separator: ", ")).")
        }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw ToolError("""
                macobar needs Screen Recording access. Ask the user to allow macobar in System Settings → Privacy & \
                Security → Screen & System Audio Recording (choosing Quit & Reopen if asked), then try again.
                """)
        }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let (filter, subject) = switch target {
        case .frontWindow: try frontWindowFilter(app: input.string("app"), in: content)
        case .screen: try screenFilter(in: content)
        }
        let configuration = SCStreamConfiguration()
        configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        configuration.showsCursor = false
        return (try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration), subject)
    }

    /// A filter for the front on-screen window of `app` (or of the frontmost app), never one of macobar's.
    private static func frontWindowFilter(app appName: String?, in content: SCShareableContent) throws -> (SCContentFilter, String) {
        let app = try RunningApps.find(appName)
        let name = app.localizedName ?? "The app"
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw ToolError("macobar can't capture its own windows. Name the app to capture, or use target screen.")
        }
        guard let window = content.windows.first(where: { $0.owningApplication?.processID == app.processIdentifier && $0.windowLayer == 0 }) else {
            throw ToolError("\(name) has no window on screen. Ask the user to show one, or use target screen.")
        }
        return (SCContentFilter(desktopIndependentWindow: window), "\(name)'s front window")
    }

    /// A filter for the main display with every macobar window left out.
    private static func screenFilter(in content: SCShareableContent) throws -> (SCContentFilter, String) {
        let mainDisplayID = CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == mainDisplayID }) ?? content.displays.first else {
            throw ToolError("No display is available to capture.")
        }
        let macobar = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        return (SCContentFilter(display: display, excludingApplications: macobar, exceptingWindows: []), "the screen")
    }
}

/// Prepares images for the model: at most `longestSide` pixels on the long side, flattened onto white, as JPEG.
private enum ModelImage {
    /// Longest side sent, in pixels; bigger images cost more tokens without helping the model.
    static let longestSide = 1280
    /// JPEG quality that keeps files small and text legible.
    private static let jpegQuality = 0.7

    /// `image` scaled down to fit `longestSide` and encoded as JPEG.
    static func jpeg(from image: CGImage) throws -> ToolImage {
        let scale = min(1, Double(longestSide) / Double(max(image.width, image.height, 1)))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        let fitted = try render(width: width, height: height) { context in
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ToolError("Couldn't encode the image as JPEG.")
        }
        CGImageDestinationAddImage(destination, fitted, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ToolError("Couldn't encode the image as JPEG.") }
        return ToolImage(data: data as Data, mediaType: "image/jpeg")
    }

    /// An opaque sRGB image of `width` × `height` pixels: white, with `draw` painted over it.
    static func render(width: Int, height: Int, draw: (CGContext) -> Void) throws -> CGImage {
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw ToolError("Couldn't prepare a \(width)×\(height) image.")
        }
        context.interpolationQuality = .high
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        draw(context)
        guard let image = context.makeImage() else { throw ToolError("Couldn't prepare a \(width)×\(height) image.") }
        return image
    }
}
