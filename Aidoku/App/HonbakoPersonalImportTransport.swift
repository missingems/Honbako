#if SUMI
import Foundation

/// Uses the native connector's normal request pacing plus MangaDex@Home's
/// tighter limit. This runs only for an explicitly requested owner import.
actor HonbakoPersonalImportTransport {
    private var nextPageServerRequest = ContinuousClock.now

    func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if request.url?.path.hasPrefix("/at-home/server/") == true {
            let clock = ContinuousClock()
            let reserved = max(clock.now, nextPageServerRequest)
            nextPageServerRequest = reserved.advanced(by: .milliseconds(1600))
            try await clock.sleep(until: reserved)
        }
        for attempt in 0...2 {
            try Task.checkCancellation()
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw HonbakoMangaDexError.invalidResponse
            }
            if attempt < 2, response.statusCode == 429 {
                let wait = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 15
                try await Task.sleep(for: .seconds(min(65, max(2, wait))))
                continue
            }
            return (data, response)
        }
        throw HonbakoMangaDexError.invalidResponse
    }
}
#endif
