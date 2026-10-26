#if SUMI && DEBUG
import Foundation

/// Explicitly enabled, aggregate-only diagnostics for the bundled public catalogs.
@MainActor
enum SumiCatalogDiagnostics {
    private static let argument = "--sumi-catalog-diagnostics"

    private struct Snapshot: Encodable {
        let processID: Int
        let generatedAt: Date
        let availableSourceKeys: [String]
        let providerFailures: [String: String]
        let searchResultCount: Int
        let resultCountsByProvider: [String: Int]
        let searchRunning: Bool
    }

    static func write(
        availableSourceKeys: [String],
        providerFailures: [String: String],
        searchResultCount: Int,
        resultCountsByProvider: [String: Int],
        searchRunning: Bool,
        redactingSearchText: String
    ) {
        guard ProcessInfo.processInfo.arguments.contains(argument),
              let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let snapshot = Snapshot(
            processID: Int(ProcessInfo.processInfo.processIdentifier),
            generatedAt: Date(),
            availableSourceKeys: availableSourceKeys.sorted(),
            providerFailures: providerFailures.mapValues {
                sanitizedError($0, redactingSearchText: redactingSearchText)
            },
            searchResultCount: searchResultCount,
            resultCountsByProvider: resultCountsByProvider,
            searchRunning: searchRunning
        )
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
            try data.write(to: caches.appendingPathComponent("SumiCatalogDiagnostics.json"), options: .atomic)
        } catch {
            LogManager.logger.error("SUMI catalog diagnostics could not be written.")
        }
    }

    private static func sanitizedError(_ message: String, redactingSearchText searchText: String) -> String {
        var result = message
        if !searchText.isEmpty {
            let encoded = searchText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchText
            for value in Set([searchText, encoded, encoded.replacingOccurrences(of: "%20", with: "+")]) {
                result = result.replacingOccurrences(of: value, with: "[search]", options: [.caseInsensitive, .diacriticInsensitive])
            }
        }
        // Provider errors can contain request URLs, whose paths or parameters may
        // echo the search or a transient credential. Neither belongs in this file.
        for pattern in [
            #"(?i)\b[a-z][a-z0-9+.-]*://[^\s<>"']+"#,
            #"(?i)\b(?:authorization|cookie|set-cookie)\s*[:=][^\r\n]*"#,
            #"(?i)\b(?:token|access[_-]?token|refresh[_-]?token|api[_-]?key)\s*[:=]\s*[^\s;,]+"#
        ] {
            result = result.replacingOccurrences(of: pattern, with: "[redacted]", options: .regularExpression)
        }
        return String(result.prefix(256))
    }
}
#endif
