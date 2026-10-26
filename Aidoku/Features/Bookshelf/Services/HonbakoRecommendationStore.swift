#if SUMI
import Combine
import Foundation

@MainActor
final class HonbakoRecommendationStore: ObservableObject {
    @Published private(set) var items: [HonbakoRecommendationFeed.Item] = []
    @Published private(set) var isLoading = false
    private let endpoint: URL
    private let cacheURL: URL
    private var lastFetch: Date?
    private var loading: Task<Void, Never>?

    init(endpoint: URL = URL(string: "https://missingems.github.io/Honbako/recommendations.json")!, cacheURL: URL? = nil) {
        self.endpoint = endpoint
        self.cacheURL = cacheURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Honbako/recommendations-cache.json")
        let cached = try? Data(contentsOf: self.cacheURL)
        let bundled = Bundle.main.url(forResource: "recommendations", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
        let cachedFeed = cached.flatMap { try? HonbakoRecommendationFeed.decode($0) }
        let bundledFeed = bundled.flatMap { try? HonbakoRecommendationFeed.decode($0) }
        items = (cachedFeed ?? bundledFeed)?.items ?? []
    }

    deinit { loading?.cancel() }

    func refresh() async {
        if let loading { await loading.value; return }
        guard lastFetch.map({ Date.now.timeIntervalSince($0) >= 900 }) ?? true else { return }
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.load()
        }
        loading = task
        await task.value
        loading = nil
    }

    private func load() async {
        guard HonbakoRecommendationFeed.Item.isPublicHTTPS(endpoint) else { return }
        isLoading = true
        defer { isLoading = false; lastFetch = .now }
        var request = URLRequest(url: endpoint, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 8)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  !Task.isCancelled else { return }
            let feed = try HonbakoRecommendationFeed.decode(data)
            items = feed.items
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            // An unavailable feed leaves the last validated or bundled catalog.
        }
    }
}
#endif
