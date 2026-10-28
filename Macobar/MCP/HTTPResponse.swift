import Foundation

/// An HTTP/1.1 response; every one closes its connection, since each connection carries one request.
struct HTTPResponse: Sendable {
    /// The status code, e.g. 200.
    let status: Int
    /// Extra headers; `Content-Length` and `Connection` are added when written.
    var headers: [String: String] = [:]
    /// The body.
    var body = Data()

    /// A response whose body is `message` as plain text, for refusals a person may read in a log.
    static func text(_ status: Int, _ message: String, headers: [String: String] = [:]) -> HTTPResponse {
        HTTPResponse(status: status, headers: headers.merging(["Content-Type": "text/plain; charset=utf-8"]) { $1 }, body: Data(message.utf8))
    }

    /// The response as bytes on the wire.
    var serialized: Data {
        let allHeaders = headers.merging(["Content-Length": String(body.count), "Connection": "close"]) { $1 }
        let headerLines = allHeaders.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)\r\n" }.joined()
        return Data("HTTP/1.1 \(status) \(reason)\r\n\(headerLines)\r\n".utf8) + body
    }

    /// The standard reason phrase for `status`.
    private var reason: String {
        switch status {
        case 200: "OK"
        case 202: "Accepted"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 411: "Length Required"
        case 413: "Content Too Large"
        default: "Status \(status)"
        }
    }
}
