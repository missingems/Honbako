#if SUMI
import AidokuRunner
import Foundation

/// An explicit personal-device operation, independent of the normal catalog UI.
/// Ranking is the source API's followedCount descending order, never invented scores.
struct HonbakoPersonalEnglishCatalog: Sendable {
    struct Entry: Sendable {
        let rank: Int
        let manga: AidokuRunner.Manga
        let chapters: [AidokuRunner.Chapter]
        let verifiedChapterID: String
        let verifiedPageCount: Int
    }

    struct Prepared: Sendable, Codable {
        let entries: [Entry]
        let errors: [String]
    }

    typealias PageLoader = @Sendable (Int) async throws -> AidokuRunner.MangaPageResult
    typealias ChapterLoader = @Sendable (AidokuRunner.Manga) async throws -> [AidokuRunner.Chapter]
    typealias PageVerifier = @Sendable (AidokuRunner.Manga, AidokuRunner.Chapter) async throws -> Int

    let pageLoader: PageLoader
    let chapterLoader: ChapterLoader
    let pageVerifier: PageVerifier
    var concurrency = 3
    var maximumPages = 10

    /// Prepares complete English chapter snapshots before touching the library.
    /// A failed candidate is skipped; a failed catalog page aborts the import.
    func prepare(count: Int = 50) async throws -> Prepared {
        guard count > 0 else { return .init(entries: [], errors: []) }
        var selected: [Entry] = []
        var errors: [String] = []
        var seen: Set<MangaIdentifier> = []
        var rank = 0
        for page in 1...max(1, maximumPages) {
            try Task.checkCancellation()
            let result = try await pageLoader(page)
            let candidates = result.entries.compactMap { manga -> Candidate? in
                rank += 1
                guard manga.sourceKey == HonbakoMangaDexRunner.sourceKey,
                      UUID(uuidString: manga.key) != nil,
                      seen.insert(manga.identifier).inserted else { return nil }
                return Candidate(rank: rank, manga: manga)
            }
            let outcomes = await validate(candidates)
            try Task.checkCancellation()
            for outcome in outcomes.sorted(by: { $0.rank < $1.rank }) {
                if let entry = outcome.entry { selected.append(entry) }
                else { errors.append(outcome.error ?? "An English title could not be verified.") }
            }
            if selected.count >= count || !result.hasNextPage || result.entries.isEmpty { break }
        }
        return .init(entries: Array(selected.prefix(count)), errors: errors)
    }

    private struct Candidate: Sendable {
        let rank: Int
        let manga: AidokuRunner.Manga
    }

    private struct Outcome: Sendable {
        let rank: Int
        let entry: Entry?
        let error: String?
    }

    private func validate(_ candidates: [Candidate]) async -> [Outcome] {
        await withTaskGroup(of: Outcome.self) { group in
            var next = 0
            let limit = min(max(1, concurrency), candidates.count)
            for _ in 0..<limit {
                let candidate = candidates[next]
                group.addTask { await validate(candidate) }
                next += 1
            }
            var results: [Outcome] = []
            for await result in group {
                results.append(result)
                if next < candidates.count {
                    let candidate = candidates[next]
                    group.addTask { await validate(candidate) }
                    next += 1
                }
            }
            return results
        }
    }

    private func validate(_ candidate: Candidate) async -> Outcome {
        do {
            try Task.checkCancellation()
            let chapters = try await chapterLoader(candidate.manga)
                .filter { $0.language?.lowercased() == "en" && !$0.locked }
            guard let firstChapter = chapters.last else {
                return .init(rank: candidate.rank, entry: nil,
                    error: "\(candidate.manga.key): No readable English chapters.")
            }
            let count = try await pageVerifier(candidate.manga, firstChapter)
            guard count > 0 else {
                return .init(rank: candidate.rank, entry: nil,
                    error: "\(candidate.manga.key): The first English chapter has no page files.")
            }
            var manga = candidate.manga
            manga.chapters = chapters
            return .init(rank: candidate.rank,
                entry: .init(rank: candidate.rank, manga: manga, chapters: chapters,
                    verifiedChapterID: firstChapter.key, verifiedPageCount: count), error: nil)
        } catch {
            // Provider errors can contain request URLs. Keep the setup receipt neutral.
            return .init(rank: candidate.rank, entry: nil,
                error: "\(candidate.manga.key): English chapter metadata or page files could not be verified.")
        }
    }
}
#endif
