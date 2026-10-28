import Foundation

/// One HTTP/1.1 request read off a socket: method, path, headers and body.
struct HTTPRequest: Equatable, Sendable {
    /// Largest header section accepted, in bytes.
    private static let maxHeaderBytes = 16_384
    /// Largest body accepted, in bytes (1 MB).
    static let maxBodyBytes = 1_048_576

    /// The method, e.g. "POST".
    let method: String
    /// The path without its query string, e.g. "/mcp".
    let path: String
    /// Header values by lowercased name.
    let headers: [String: String]
    /// The body, exactly `Content-Length` bytes.
    let body: Data

    /// The request at the start of `data`, nil while more bytes are needed, or an error when it can't be served.
    static func parse(_ data: Data) throws(HTTPRequestError) -> HTTPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
            if data.count > maxHeaderBytes { throw .tooLarge }
            return nil
        }
        guard headerEnd.lowerBound - data.startIndex <= maxHeaderBytes else { throw .tooLarge }
        let lines = String(decoding: data[..<headerEnd.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        guard let requestLine = lines.first?.split(separator: " "), requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else {
            throw .malformed
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { throw .malformed }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard headers["transfer-encoding"] == nil else { throw .lengthRequired }
        let length = try bodyLength(headers["content-length"])
        let bodyStart = headerEnd.upperBound
        guard data.endIndex - bodyStart >= length else { return nil }
        return HTTPRequest(
            method: String(requestLine[0]),
            path: String(requestLine[1].prefix { $0 != "?" }),
            headers: headers,
            body: Data(data[bodyStart..<bodyStart + length])
        )
    }

    /// The body length a `Content-Length` value promises; no header means no body.
    private static func bodyLength(_ value: String?) throws(HTTPRequestError) -> Int {
        guard let value else { return 0 }
        guard let length = Int(value), length >= 0 else { throw .malformed }
        guard length <= maxBodyBytes else { throw .tooLarge }
        return length
    }
}

/// Why a request was turned away before it reached MCP.
enum HTTPRequestError: Error, Equatable {
    /// Not a valid HTTP/1.1 request.
    case malformed
    /// Headers or body over the size limits.
    case tooLarge
    /// A chunked body; only `Content-Length` bodies are read.
    case lengthRequired
}
