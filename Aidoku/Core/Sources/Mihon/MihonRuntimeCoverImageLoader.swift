import AidokuRunner
import CryptoKit
import Foundation
import Nuke

/// Shared by search/library cover warming and generic cover views. A missing
/// runtime provider produces a failed lazy request, never a raw HTTP request.
enum MihonRuntimeCoverImageLoader {
    static func handles(url: URL, source: AidokuRunner.Source?, sourceKey: String? = nil) -> Bool {
        guard !url.isFileURL, url.toAidokuFileUrl() == nil else { return false }
        return (sourceKey ?? source?.key)?.hasPrefix("mihon.") == true
            || source?.runner is any MihonRuntimeCoverImageProviding
            || source?.runner is any MihonRuntimeImageProviding
            || url.scheme?.lowercased() == MihonRunner.imageScheme
    }

    static func cacheScope(source: AidokuRunner.Source?) -> String? {
        (source?.runner as? any MihonRuntimeCoverImageProviding)?.runtimeCoverCacheScope
    }

    static func imageRequest(url: URL, source: AidokuRunner.Source?, sourceKey: String? = nil,
                             processors: [any ImageProcessing] = []) -> ImageRequest? {
        guard handles(url: url, source: source, sourceKey: sourceKey) else { return nil }
        let key = sourceKey ?? source?.key ?? "missing-source"
        let scope = cacheScope(source: source) ?? "unavailable"
        // Keep even invalid provider input bounded in the cache identifier. The
        // lazy provider performs strict validation before invoking the runtime.
        let providerKey = (source?.runner as? any MihonRuntimeCoverImageProviding)?.runtimeCoverSourceKey ?? "unavailable"
        let scopeData = Data([String(scope.prefix(4_097)), String(providerKey.prefix(256)), String((source?.key ?? "missing-source").prefix(256))].joined(separator: "\n").utf8)
        let urlData = Data(url.absoluteString.prefix(16_385).utf8)
        let identifier = "honbako.runtime.cover.\(key.prefix(256)).\(digest(scopeData)).\(digest(urlData))"
        return ImageRequest(id: identifier, data: {
            try await imageData(url: url, source: source, sourceKey: sourceKey).data
        }, processors: processors, userInfo: [.processesKey: false])
    }

    static func imageData(url: URL, source: AidokuRunner.Source?, sourceKey: String? = nil) async throws -> MihonRuntimeImagePayload {
        try Task.checkCancellation()
        guard let source, sourceKey == nil || sourceKey == source.key,
              let provider = source.runner as? any MihonRuntimeCoverImageProviding else {
            throw MihonRuntimeError.imageLoaderRequired
        }
        guard provider.runtimeCoverSourceKey == source.key,
              source.key.hasPrefix("mihon."),
              (try? MihonRepositoryCatalog.exactID(String(source.key.dropFirst("mihon.".count)))) == String(source.key.dropFirst("mihon.".count)),
              !provider.runtimeCoverCacheScope.isEmpty, provider.runtimeCoverCacheScope.utf8.count <= 4_096 else {
            throw MihonRuntimeError.identityMismatch
        }
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false,
              url.user == nil, url.password == nil, url.absoluteString.utf8.count <= 16_384,
              !url.absoluteString.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else {
            throw MihonRuntimeError.invalidInput
        }
        let payload = try await provider.runtimeCoverData(url: url)
        try Task.checkCancellation()
        guard !payload.data.isEmpty else { throw MihonRuntimeError.invalidImage }
        guard payload.data.count <= MihonRunner.maximumImageBytes else { throw MihonRuntimeError.payloadTooLarge }
        if let count = payload.reportedByteCount, count != payload.data.count { throw MihonRuntimeError.invalidImage }
        if let hash = payload.reportedSHA256, hash != digest(payload.data) { throw MihonRuntimeError.invalidImage }
        if let type = payload.mediaType {
            let normalized = type.lowercased().split(separator: ";").first.map(String.init) ?? ""
            guard type.utf8.count <= 256,
                  !type.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }),
                  normalized.hasPrefix("image/") || normalized == "application/octet-stream" else { throw MihonRuntimeError.invalidImage }
        }
        try Task.checkCancellation()
        return payload
    }

    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
