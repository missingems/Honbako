import Foundation

/// Covers have their own runtime entry point. Treating a cover as a page with
/// nil context would bypass the source's cover headers/client and page hooks.
protocol MihonRuntimeCoverImageProviding: Sendable {
    var runtimeCoverSourceKey: String { get }
    /// Stable for a package revision, source, language and preferences. A new
    /// revision must not reuse cached cover bytes from a previous runtime scope.
    var runtimeCoverCacheScope: String { get }
    func runtimeCoverData(url: URL) async throws -> MihonRuntimeImagePayload
}

protocol MihonRuntimeCoverTransport: MihonRuntimeTransport {
    func coverData(session: MihonRuntimeSession, url: URL) async throws -> MihonRuntimeImagePayload
}

extension MihonJSONRuntimeTransport: MihonRuntimeCoverTransport {}
