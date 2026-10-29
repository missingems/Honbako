#if SUMI
import AidokuRunner
import Foundation

extension AidokuRunner.Source {
    static func honbakoMangaDex() -> AidokuRunner.Source {
        .init(key: HonbakoMangaDexRunner.sourceKey, name: "MangaDex", version: 1,
            languages: HonbakoMangaDexRunner.languages,
            urls: [URL(string: "https://mangadex.org")!], contentRating: .containsNsfw,
            config: .init(languageSelectType: .multiple),
            staticListings: [.init(id: "popular", name: "Popular"), .init(id: "latest", name: "Latest Updates")],
            runner: HonbakoMangaDexRunner())
    }
}

/// An independent native connector based on the public MangaDex REST schema.
/// Uses public read endpoints; no extension executable, scraping or copied adapter.
actor HonbakoMangaDexRunner: AidokuRunner.Runner {
    nonisolated static let sourceKey = "honbako.mangadex"
    nonisolated static let languages = ["en", "es", "es-419", "fr", "de", "it", "pt", "pt-BR",
        "ru", "uk", "zh-Hans", "zh-Hant", "ja", "ko", "id", "vi", "th", "ar", "pl", "tr", "nl",
        "cs", "hu", "ro", "fi", "sv", "no", "da", "el", "he", "hi", "bn", "ms", "fil", "sq",
        "az", "bg", "my", "ca", "hr", "eo", "et", "ka", "kk", "la", "lt", "mn", "ne", "fa",
        "sr", "sk", "sl", "ta", "te"]
    nonisolated let features = AidokuRunner.SourceFeatures(providesListings: true, providesImageRequests: true)

    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let transport: Transport
    private let defaults: UserDefaults
    private let requestInterval: Duration
    private var nextRequest = ContinuousClock.now
    private var titleCache: [String: (title: HonbakoMangaDexAPI.Title, date: Date)] = [:]
    private var probeCache: [String: (chapter: AidokuRunner.Chapter?, date: Date)] = [:]
    private let metadataLifetime: TimeInterval = 180
    private let now: @Sendable () -> Date
    private var pageDeliveries: [String: HonbakoMangaDexPageDelivery] = [:]
    private var pageDeliveryTasks: [String: Task<HonbakoMangaDexAPI.PageServer, Error>] = [:]
    private var nextPageServerRequest = ContinuousClock.now

    init(defaults: UserDefaults = .standard, requestInterval: Duration = .milliseconds(250),
         now: @escaping @Sendable () -> Date = { .now },
         transport: @escaping Transport = HonbakoMangaDexRunner.fetch) {
        self.defaults = defaults
        self.requestInterval = requestInterval
        self.transport = transport
        self.now = now
    }

    nonisolated private static func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw HonbakoMangaDexError.invalidResponse }
        return (data, response)
    }

    func getSearchMangaList(query: String?, page: Int, filters: [AidokuRunner.FilterValue]) async throws -> AidokuRunner.MangaPageResult {
        try await search(query: query, page: page, order: query?.isEmpty == false ? "relevance" : "followedCount")
    }

    func getMangaList(listing: AidokuRunner.Listing, page: Int) async throws -> AidokuRunner.MangaPageResult {
        try await search(query: nil, page: page, order: listing.id == "latest" ? "latestUploadedChapter" : "followedCount")
    }

    private func search(query: String?, page: Int, order: String) async throws -> AidokuRunner.MangaPageResult {
        guard (1...500).contains(page) else { return .init(entries: [], hasNextPage: false) }
        let languages = selectedLanguages()
        let offset = (page - 1) * 20
        var parameters = detailParameters() + contentParameters()
        parameters += [.init(name: "limit", value: "20"), .init(name: "offset", value: String(offset)),
            .init(name: "order[\(order)]", value: "desc"), .init(name: "hasAvailableChapters", value: "true")]
        if let query = query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            parameters.append(.init(name: "title", value: String(query.prefix(200))))
        }
        parameters += languages.map { .init(name: "availableTranslatedLanguage[]", value: HonbakoMangaDexAPI.apiLanguage($0)) }
        let response: HonbakoMangaDexAPI.Collection<HonbakoMangaDexAPI.Title> = try await request("/manga", parameters)
        guard response.result == "ok" else { throw HonbakoMangaDexError.invalidResponse }
        let titles = response.data.filter { UUID(uuidString: $0.id) != nil }
        for title in titles { cache(title) }
        return .init(entries: titles.map { $0.manga(preferredLanguages: languages) },
            hasNextPage: response.offset + response.data.count < min(response.total, 10_000))
    }

    func prepareSearchResult(_ manga: AidokuRunner.Manga) async throws -> HonbakoMangaDexSearchPreparation {
        let title = try await details(for: manga.key)
        let languages = selectedLanguages()
        let probeKey = manga.key + "|" + languages.sorted().joined(separator: ",")
        let readableChapter: AidokuRunner.Chapter?
        if let cached = probeCache[probeKey], Date.now.timeIntervalSince(cached.date) < 60 {
            readableChapter = cached.chapter
        } else {
            let response = try await feed(mangaKey: manga.key, languages: languages, limit: 1, offset: 0)
            readableChapter = response.data.first(where: { $0.isReadable(at: .now) })?.chapter()
            if probeCache.count >= 80 { probeCache.removeAll(keepingCapacity: true) }
            probeCache[probeKey] = (readableChapter, .now)
        }
        return .init(manga: title.manga(preferredLanguages: languages), readableChapter: readableChapter,
            translatedLanguages: title.translatedLanguages, releaseYear: title.attributes.year)
    }

    func getMangaUpdate(manga: AidokuRunner.Manga, needsDetails: Bool, needsChapters: Bool) async throws -> AidokuRunner.Manga {
        var result = manga
        if needsDetails { result = manga.copy(from: try await details(for: manga.key).manga(preferredLanguages: selectedLanguages())) }
        if needsChapters { result.chapters = try await chapters(for: manga, languages: selectedLanguages()) }
        return result
    }

    /// Language is explicit and local to this call; source preferences are never changed.
    func chapters(for manga: AidokuRunner.Manga, language: String) async throws -> [AidokuRunner.Chapter] {
        let language = HonbakoMangaDexAPI.canonicalLanguage(language)
        guard HonbakoMangaDexAPI.isValidLanguage(language) else {
            throw HonbakoMangaDexError.invalidResponse
        }
        if !Self.languages.contains(where: { HonbakoMangaDexAPI.canonicalLanguage($0) == language }) {
            guard try await availableLanguages(for: manga).contains(language) else {
                throw HonbakoMangaDexError.unavailableLanguage
            }
        }
        return try await chapters(for: manga, languages: [language])
    }

    /// Authoritative title metadata, rather than the reviewed catalog's
    /// non-exhaustive language coverage, controls the reader's choices.
    func availableLanguages(for manga: AidokuRunner.Manga) async throws -> [String] {
        try await details(for: manga.key).translatedLanguages
    }

    private func chapters(for manga: AidokuRunner.Manga, languages: [String]) async throws -> [AidokuRunner.Chapter] {
        var offset = 0
        var results: [AidokuRunner.Chapter] = []
        var seen: Set<String> = []
        while true {
            let response = try await feed(mangaKey: manga.key, languages: languages, limit: 500, offset: offset)
            results += response.data.filter { $0.isReadable(at: .now) && seen.insert($0.id).inserted }.map { $0.chapter() }
            let next = response.offset + response.data.count
            if next >= response.total { break }
            guard !response.data.isEmpty, next > offset, next < 10_000 else { throw HonbakoMangaDexError.tooManyChapters }
            offset = next
            try Task.checkCancellation()
        }
        return results
    }

    func getPageList(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter) async throws -> [AidokuRunner.Page] {
        try Task.checkCancellation()
        try validateIdentifier(chapter.key)
        guard !chapter.locked else { throw HonbakoMangaDexError.unavailableChapter }
        let delivery = try await pageDelivery(chapterID: chapter.key)
        try Task.checkCancellation()
        return try delivery.pages(chapterID: chapter.key)
    }

    func getImageRequest(url: String, context: PageContext?) async throws -> URLRequest {
        try Task.checkCancellation()
        guard let original = URL(string: url) else { throw HonbakoMangaDexError.invalidResponse }
        guard let identity = HonbakoMangaDexPageDelivery.identity(url: original, context: context) else {
            return HonbakoMangaDexPageDelivery.imageRequest(url: original, reload: false)
        }
        let delivery = try await pageDelivery(chapterID: identity.chapterID)
        try Task.checkCancellation()
        guard let resolved = try delivery.url(at: identity.index) else {
            throw HonbakoMangaDexError.unavailableChapter
        }
        return HonbakoMangaDexPageDelivery.imageRequest(url: resolved, reload: false)
    }

    /// One bounded image-level retry may renew the temporary @Home assignment.
    /// Simultaneous failed leaves join the same request; a short cooldown also
    /// coalesces failures that arrive just after that request has completed.
    func recoveryImageRequest(url: URL, context: PageContext?) async throws -> URLRequest? {
        guard let identity = HonbakoMangaDexPageDelivery.identity(url: url, context: context) else { return nil }
        try Task.checkCancellation()
        let cached = pageDeliveries[identity.chapterID]
        let recentlyRecovered = cached?.recoveredAt.map {
            now().timeIntervalSince($0) < HonbakoMangaDexPageDelivery.recoveryCooldown
        } == true
        let delivery = try await pageDelivery(chapterID: identity.chapterID, forceRefresh: !recentlyRecovered)
        try Task.checkCancellation()
        guard let resolved = try delivery.url(at: identity.index) else {
            throw HonbakoMangaDexError.unavailableChapter
        }
        return HonbakoMangaDexPageDelivery.imageRequest(url: resolved, reload: true)
    }

    private func pageDelivery(chapterID: String, forceRefresh: Bool = false) async throws -> HonbakoMangaDexPageDelivery {
        try validateIdentifier(chapterID)
        if let task = pageDeliveryTasks[chapterID] {
            let response = try await task.value
            return .init(response: response, resolvedAt: now(), recoveredAt: now())
        }
        if !forceRefresh, let cached = pageDeliveries[chapterID],
           now().timeIntervalSince(cached.resolvedAt) < HonbakoMangaDexPageDelivery.lifetime { return cached }
        let task = Task { [self] in
            let response: HonbakoMangaDexAPI.PageServer = try await request("/at-home/server/\(chapterID)",
                [.init(name: "forcePort443", value: "true")], cachePolicy: .reloadIgnoringLocalCacheData)
            _ = try response.pages()
            return response
        }
        pageDeliveryTasks[chapterID] = task
        defer { pageDeliveryTasks[chapterID] = nil }
        let response = try await task.value
        let date = now()
        let delivery = HonbakoMangaDexPageDelivery(response: response, resolvedAt: date,
            recoveredAt: forceRefresh ? date : nil)
        if pageDeliveries.count >= 16, let oldest = pageDeliveries.min(by: { $0.value.resolvedAt < $1.value.resolvedAt })?.key {
            pageDeliveries.removeValue(forKey: oldest)
        }
        pageDeliveries[chapterID] = delivery
        return delivery
    }

    private func feed(mangaKey: String, languages: [String], limit: Int, offset: Int)
        async throws -> HonbakoMangaDexAPI.Collection<HonbakoMangaDexAPI.Chapter> {
        try validateIdentifier(mangaKey)
        var parameters = contentParameters() + [
            URLQueryItem(name: "limit", value: String(limit)), .init(name: "offset", value: String(offset)),
            .init(name: "includeEmptyPages", value: "0"), .init(name: "includeExternalUrl", value: "0"),
            .init(name: "includeFutureUpdates", value: "0"), .init(name: "includeFuturePublishAt", value: "0"),
            .init(name: "includeUnavailable", value: "0"), .init(name: "includes[]", value: "scanlation_group"),
            .init(name: "order[volume]", value: "desc"), .init(name: "order[chapter]", value: "desc")]
        parameters += languages.map { .init(name: "translatedLanguage[]", value: HonbakoMangaDexAPI.apiLanguage($0)) }
        let response: HonbakoMangaDexAPI.Collection<HonbakoMangaDexAPI.Chapter> =
            try await request("/manga/\(mangaKey)/feed", parameters)
        guard response.result == "ok" else { throw HonbakoMangaDexError.invalidResponse }
        return response
    }

    private func details(for id: String) async throws -> HonbakoMangaDexAPI.Title {
        try validateIdentifier(id)
        if let cached = titleCache[id], Date.now.timeIntervalSince(cached.date) < metadataLifetime { return cached.title }
        let response: HonbakoMangaDexAPI.Entity<HonbakoMangaDexAPI.Title> = try await request("/manga/\(id)", detailParameters())
        guard response.result == "ok", response.data.id == id else { throw HonbakoMangaDexError.invalidResponse }
        cache(response.data)
        return response.data
    }

    private func cache(_ title: HonbakoMangaDexAPI.Title) {
        if titleCache.count >= 80 { titleCache.removeAll(keepingCapacity: true) }
        titleCache[title.id] = (title, .now)
    }

    func selectedChapterLanguages() -> [String] { selectedLanguages() }

    private func selectedLanguages() -> [String] {
        let values = defaults.stringArray(forKey: Self.sourceKey + ".languages")
            ?? defaults.string(forKey: Self.sourceKey + ".language").map { [$0] } ?? ["en"]
        let allowed = Set(Self.languages.map(HonbakoMangaDexAPI.canonicalLanguage))
        let selected = Array(Set(values.map(HonbakoMangaDexAPI.canonicalLanguage))).filter(allowed.contains).sorted()
        return selected.isEmpty ? ["en"] : selected
    }

    private func detailParameters() -> [URLQueryItem] {
        ["author", "artist", "cover_art"].map { .init(name: "includes[]", value: $0) }
    }

    private func contentParameters() -> [URLQueryItem] {
        ["safe", "suggestive"].map { .init(name: "contentRating[]", value: $0) }
    }

    private func validateIdentifier(_ value: String) throws {
        guard UUID(uuidString: value) != nil else { throw HonbakoMangaDexError.invalidIdentifier }
    }

    private func request<Value: Decodable>(_ path: String, _ parameters: [URLQueryItem],
                                           cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy) async throws -> Value {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.mangadex.org"
        components.path = path
        components.queryItems = parameters
        guard let url = components.url else { throw HonbakoMangaDexError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: cachePolicy, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Honbako/0.2 (https://github.com/missingems/Honbako)", forHTTPHeaderField: "User-Agent")
        let now = ContinuousClock.now
        let isPageServer = path.hasPrefix("/at-home/server/")
        let slot = isPageServer ? max(max(now, nextRequest), nextPageServerRequest) : max(now, nextRequest)
        nextRequest = slot.advanced(by: requestInterval)
        if isPageServer {
            nextPageServerRequest = slot.advanced(by: requestInterval == .zero ? .zero : .milliseconds(1_500))
        }
        if slot > now { try await Task.sleep(until: slot, clock: .continuous) }
        try Task.checkCancellation()
        let (data, response) = try await transport(request)
        guard (200..<300).contains(response.statusCode) else { throw HonbakoMangaDexError.requestFailed(response.statusCode) }
        guard data.count <= 8_000_000 else { throw HonbakoMangaDexError.invalidResponse }
        return try JSONDecoder().decode(Value.self, from: data)
    }
}
#endif
