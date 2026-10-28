import Foundation

/// Reads what a tools/call result holds: its text and images, or the tool's error.
enum MCPToolOutput {
    /// Image types every provider accepts; others (such as SVG) are left out, since one would fail the whole model request.
    private static let acceptedImageTypes: Set<String> = ["image/png", "image/jpeg", "image/gif", "image/webp"]
    /// Largest image kept, in bytes; providers refuse larger ones, which would fail the whole model request.
    private static let maximumImageBytes = 5 << 20

    /// The joined text content (or the structured content when there's no text) and the images; throws when `isError` is set.
    static func parse(_ result: JSONValue) throws -> (text: String, images: [ToolImage]) {
        let content = result["content"]?.array ?? []
        var text = content.compactMap { $0["type"]?.string == "text" ? $0["text"]?.string : nil }.joined(separator: "\n")
        if text.isEmpty, let structured = result["structuredContent"] { text = structured.jsonString }
        guard result["isError"]?.bool != true else {
            throw ToolError(text.isEmpty ? "The tool failed without saying why." : text)
        }
        let images = content.compactMap { item -> ToolImage? in
            guard item["type"]?.string == "image", let base64 = item["data"]?.string, let data = Data(base64Encoded: base64),
                data.count <= maximumImageBytes, let mediaType = item["mimeType"]?.string, acceptedImageTypes.contains(mediaType) else { return nil }
            return ToolImage(data: data, mediaType: mediaType)
        }
        return (text, images)
    }
}
