import Foundation

/// Streams into a caller-owned staging file; never buffers an unbounded HTTP
/// response. No cookies, cached responses, credentials, or repository headers
/// are forwarded to a redirected host.
enum MihonPackageDownload {
    static func permits(_ url: URL) -> Bool {
        guard url.absoluteString.utf8.count <= 8_192, url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil, url.fragment == nil,
              !url.absoluteString.contains("\\"),
              !url.absoluteString.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else { return false }
        return true
    }

    static func download(_ url: URL, to destination: URL, maximumBytes: Int) async throws {
        guard permits(url), maximumBytes > 0 else { throw MihonExtensionPackageStore.Failure.invalidCandidate }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        let delegate = RedirectPolicy()
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              let finalURL = response.url, permits(finalURL) else { throw MihonExtensionPackageStore.Failure.downloadRejected }
        guard response.expectedContentLength <= Int64(maximumBytes) else { throw MihonExtensionPackageStore.Failure.packageTooLarge }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw MihonExtensionPackageStore.Failure.unsafeStorePath
        }
        let file = try FileHandle(forWritingTo: destination)
        defer { try? file.close() }
        var buffer = Data()
        buffer.reserveCapacity(64 * 1_024)
        var count = 0
        for try await byte in bytes {
            try Task.checkCancellation()
            guard count < maximumBytes else { throw MihonExtensionPackageStore.Failure.packageTooLarge }
            count += 1
            buffer.append(byte)
            if buffer.count == 64 * 1_024 {
                try file.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        try file.write(contentsOf: buffer)
        try file.synchronize()
        try Task.checkCancellation()
    }

    private final class RedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var redirects = 0

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            let allowed = lock.withLock { redirects += 1; return redirects <= 5 }
            guard allowed, let url = request.url, MihonPackageDownload.permits(url) else {
                completionHandler(nil)
                return
            }
            // Reconstruct rather than forwarding potentially sensitive headers.
            var redirected = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            redirected.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
            completionHandler(redirected)
        }
    }
}
