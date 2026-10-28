import AppKit
import PDFKit

/// Reads the plain text of the document types knowledge search indexes.
enum DocumentText {
    /// Extensions read as plain text.
    private static let plainTextExtensions: Set = ["txt", "text", "md", "markdown"]
    /// Extensions read through `NSAttributedString`, with the importer each needs.
    private static let richTextTypes: [String: NSAttributedString.DocumentType] = ["rtf": .rtf, "doc": .docFormat, "docx": .officeOpenXML]
    /// Every extension that can be indexed.
    static let supportedExtensions = plainTextExtensions.union(richTextTypes.keys).union(["pdf"])

    /// The text of the file at `url`, read off the caller's actor; empty when it can't be read.
    @concurrent static func text(of url: URL) async -> String {
        let fileExtension = url.pathExtension.lowercased()
        if fileExtension == "pdf" { return PDFDocument(url: url)?.string ?? "" }
        if let documentType = richTextTypes[fileExtension] {
            // An explicit type keeps the import away from WebKit, so it's safe off the main thread.
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: documentType]
            return (try? NSAttributedString(url: url, options: options, documentAttributes: nil).string) ?? ""
        }
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        var encoding = String.Encoding.utf8
        return (try? String(contentsOf: url, usedEncoding: &encoding)) ?? ""
    }
}
