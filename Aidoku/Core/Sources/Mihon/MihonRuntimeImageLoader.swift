import AidokuRunner
import CryptoKit
import Foundation
import Nuke

/// The shared lazy boundary for reader pages, previews, preloading and offline
/// downloads. Runtime-produced bytes already include the extension image hooks.
enum MihonRuntimeImageLoader {
    static func handles(url: URL, source: AidokuRunner.Source?) -> Bool {
        url.scheme?.lowercased() == MihonRunner.imageScheme
            || (!url.isFileURL && source?.runner is any MihonRuntimeImageProviding)
    }

    /// Nil means the ordinary source/file path should be used. An invalid
    /// runtime request instead returns a failing lazy task, never an HTTP task.
    static func imageRequest(url: URL, context: AidokuRunner.PageContext?, source: AidokuRunner.Source?,
                             processors: [any ImageProcessing]) -> ImageRequest? {
        guard handles(url: url, source: source) else { return nil }
        let sourceKey = source?.key ?? "missing-source"
        let contextData = boundedContext(context)
            ? ((try? JSONSerialization.data(withJSONObject: context ?? [:], options: [.sortedKeys])) ?? Data()) : Data()
        let providerState = source?.runner is any MihonRuntimeImageProviding ? "provider" : "unavailable"
        let identifier = "honbako.runtime.\(providerState).\(sourceKey).\(url.absoluteString).\(digest(contextData))"
        return ImageRequest(id: identifier, data: {
            try await imageData(url: url, context: context, source: source).data
        }, processors: processors, userInfo: [.processesKey: false])
    }

    static func imageData(url: URL, context: AidokuRunner.PageContext?, source: AidokuRunner.Source?) async throws -> MihonRuntimeImagePayload {
        try Task.checkCancellation()
        guard url.scheme?.lowercased() == MihonRunner.imageScheme, url.host == "runtime",
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              let source else { throw MihonRuntimeError.invalidPageContext }
        let parts = url.pathComponents
        guard parts.count == 3, (try? MihonRepositoryCatalog.exactID(parts[1])) == parts[1],
              source.key == "mihon.\(parts[1])", parts[2].count == 64,
              parts[2].utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              let context, !context.isEmpty, boundedContext(context) else { throw MihonRuntimeError.invalidPageContext }
        guard let provider = source.runner as? any MihonRuntimeImageProviding else { throw MihonRuntimeError.imageLoaderRequired }
        let payload = try await provider.runtimeImageData(url: url, context: context)
        try Task.checkCancellation()
        guard !payload.data.isEmpty else { throw MihonRuntimeError.invalidImage }
        guard payload.data.count <= MihonRunner.maximumImageBytes else { throw MihonRuntimeError.payloadTooLarge }
        if let count = payload.reportedByteCount, count != payload.data.count { throw MihonRuntimeError.invalidImage }
        if let hash = payload.reportedSHA256, hash != digest(payload.data) { throw MihonRuntimeError.invalidImage }
        if let type = payload.mediaType {
            let normalized = type.lowercased().split(separator: ";").first.map(String.init) ?? ""
            guard type.utf8.count <= 256,
                  !type.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }),
                  normalized.hasPrefix("image/") || normalized == "application/octet-stream" else {
                throw MihonRuntimeError.invalidImage
            }
        }
        try Task.checkCancellation()
        return payload
    }

    static func fileExtension(for payload: MihonRuntimeImagePayload) -> String {
        // Prefer known file signatures if a provider's HTTP MIME is inaccurate.
        let bytes = payload.data
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "png" }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if bytes.starts(with: Array("GIF8".utf8)) { return "gif" }
        if bytes.count >= 12, bytes.prefix(4) == Data("RIFF".utf8), bytes.dropFirst(8).prefix(4) == Data("WEBP".utf8) { return "webp" }
        let type = payload.mediaType?.lowercased().split(separator: ";").first.map(String.init) ?? ""
        return ["image/png": "png", "image/jpeg": "jpg", "image/gif": "gif", "image/webp": "webp",
                "image/avif": "avif", "image/heic": "heic", "image/heif": "heif", "image/jxl": "jxl",
                "image/bmp": "bmp", "image/tiff": "tiff"][type] ?? "png"
    }

    private static func boundedContext(_ context: AidokuRunner.PageContext?) -> Bool {
        guard let context else { return false }
        guard context.count <= 64 else { return false }
        var count = 0
        for (key, value) in context {
            count += key.utf8.count + value.utf8.count
            if count > 128 * 1024 { return false }
        }
        return true
    }

    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
