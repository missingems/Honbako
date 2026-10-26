#if SUMI
import AidokuRunner
import Foundation

/// The source runner does not expose publication dates. Enrich only an exact
/// MangaDex entity with its documented release year, publication status, and authors.
actor SumiSearchMetadataService {
    struct Metadata: Equatable, Sendable {
        let authors: [String]
        let releaseYear: Int?
        let isOngoing: Bool?
        let publishingStatus: AidokuRunner.PublishingStatus?

        init(authors: [String], releaseYear: Int?, isOngoing: Bool? = nil, publishingStatus: AidokuRunner.PublishingStatus? = nil) {
            self.authors = authors
            self.releaseYear = releaseYear
            let knownStatus = publishingStatus.flatMap { $0 == .unknown ? nil : $0 }
            self.publishingStatus = knownStatus
            self.isOngoing = knownStatus.map { $0 == .ongoing } ?? isOngoing
        }
    }

    typealias Loader = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    static let shared = SumiSearchMetadataService()
    private let loader: Loader
    private var cache: [UUID: CacheEntry] = [:]
    private var active: Set<UUID> = []
    private var nextRequestAt = ContinuousClock.now
    private var serverCooldown = Date.distantPast

    private struct CacheEntry {
        let metadata: Metadata?
        let expires: Date
        let stored: Date
    }

    init(loader: @escaping Loader = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, response)
    }) {
        self.loader = loader
    }

    func metadata(for book: SumiBook) async -> Metadata? {
        guard let id = Self.mangaID(for: book), serverCooldown <= .now else { return nil }
        if let entry = cache[id], entry.expires > .now { return entry.metadata }
        // Requests cancel with their visible row. A second view of an in-flight
        // title waits for its cached answer instead of issuing a duplicate.
        while active.count >= 2 || active.contains(id) || ContinuousClock.now < nextRequestAt {
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return nil }
            guard serverCooldown <= .now else { return nil }
            if let entry = cache[id], entry.expires > .now { return entry.metadata }
        }
        guard !Task.isCancelled else { return nil }
        active.insert(id)
        nextRequestAt = .now.advanced(by: .milliseconds(500))
        defer { active.remove(id) }
        var request = URLRequest(url: Self.url(for: id))
        request.timeoutInterval = 8
        request.setValue("Honbako/0.11", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await loader(request)
            try Task.checkCancellation()
            guard response.statusCode == 200 else {
                if response.statusCode == 429 {
                    let retry = Double(response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60
                    serverCooldown = .now.addingTimeInterval(max(60, retry))
                }
                store(nil, for: id, lifetime: 300)
                return nil
            }
            let result = try Self.decode(data, requestedID: id)
            store(result, for: id, lifetime: 86_400)
            return result
        } catch is CancellationError {
            return nil
        } catch {
            guard !Task.isCancelled else { return nil }
            store(nil, for: id, lifetime: 300)
            return nil
        }
    }

    private func store(_ metadata: Metadata?, for id: UUID, lifetime: TimeInterval) {
        if cache.count >= 256, cache[id] == nil, let oldest = cache.min(by: { $0.value.stored < $1.value.stored })?.key {
            cache.removeValue(forKey: oldest)
        }
        cache[id] = CacheEntry(metadata: metadata, expires: .now.addingTimeInterval(lifetime), stored: .now)
    }

    static func mangaID(for book: SumiBook) -> UUID? {
        guard book.sourceKey == "multi.mangadex" else { return nil }
        if let id = UUID(uuidString: book.manga.key) { return id }
        guard let url = book.manga.url, ["mangadex.org", "www.mangadex.org"].contains(url.host?.lowercased() ?? ""),
              let titleIndex = url.pathComponents.firstIndex(of: "title"),
              url.pathComponents.indices.contains(titleIndex + 1) else { return nil }
        return UUID(uuidString: url.pathComponents[titleIndex + 1])
    }

    static func url(for id: UUID) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.mangadex.org"
        components.path = "/manga/\(id.uuidString.lowercased())"
        components.queryItems = [URLQueryItem(name: "includes[]", value: "author")]
        // Components are entirely static except for a validated Foundation UUID.
        return components.url!
    }

    static func decode(_ data: Data, requestedID: UUID) throws -> Metadata {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.result == "ok", response.data.type == "manga", response.data.id == requestedID else {
            throw URLError(.badServerResponse)
        }
        var names: [String] = []
        for author in response.data.relationships ?? [] where author.type == "author" {
            guard let name = author.attributes?.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty, !names.contains(name) else { continue }
            names.append(name)
        }
        let year = response.data.attributes.year.flatMap { (1...9999).contains($0) ? $0 : nil }
        let publishingStatus: AidokuRunner.PublishingStatus?
        switch response.data.attributes.status {
        case "ongoing": publishingStatus = .ongoing
        case "completed": publishingStatus = .completed
        case "hiatus": publishingStatus = .hiatus
        case "cancelled": publishingStatus = .cancelled
        default: publishingStatus = nil
        }
        return Metadata(authors: names, releaseYear: year, publishingStatus: publishingStatus)
    }

    private struct Response: Decodable {
        let result: String
        let data: Manga
        struct Manga: Decodable {
            let id: UUID
            let type: String
            let attributes: Attributes
            let relationships: [Relationship]?
        }
        struct Attributes: Decodable {
            let year: Int?
            let status: String?
        }
        struct Relationship: Decodable {
            let type: String
            let attributes: Author?
        }
        struct Author: Decodable { let name: String? }
    }
}
#endif
