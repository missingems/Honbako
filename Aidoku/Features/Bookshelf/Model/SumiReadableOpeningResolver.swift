#if SUMI
import Foundation

/// Resolve only when opening a book, never while rendering its chapter rows.
/// Known missing/locked chapters cost no request. After the request budget is
/// exhausted, a later downloaded/cached readable chapter can still be selected.
@MainActor
enum SumiReadableOpeningResolver {
    static func resolve(
        _ choices: [SumiReaderOpeningPolicy.Choice], maximumProbes: Int = 12,
        state: (SumiReaderOpeningPolicy.Choice) -> HonbakoChapterAvailability.State,
        probe: (SumiReaderOpeningPolicy.Choice) async throws -> Bool
    ) async throws -> SumiReaderOpeningPolicy.Choice? {
        var attempted: Set<String> = []
        var probes = 0
        for choice in choices {
            try Task.checkCancellation()
            guard attempted.insert(choice.chapterKey).inserted else { continue }
            switch state(choice) {
            case .available: return choice
            case .unavailable: continue
            case .unknown: break
            }
            guard probes < max(0, maximumProbes) else { continue }
            probes += 1
            do {
                if try await probe(choice) { return choice }
            } catch {
                // Offline, authorization, rate limits and malformed responses
                // remain retryable; do not fan the same failure across a book.
                guard HonbakoChapterAvailability.confirmsUnavailable(error) else { throw error }
            }
        }
        return nil
    }
}
#endif
