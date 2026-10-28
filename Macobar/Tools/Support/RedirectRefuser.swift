import Foundation

/// Stops a request at a redirect, so the caller sees the redirect itself: web fetches check the new address first, and model requests never carry an API key to another host.
final class RedirectRefuser: NSObject, URLSessionTaskDelegate, Sendable {
    /// Declines every redirect; the redirect response itself is returned.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}
