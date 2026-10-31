#if SUMI && DEBUG
import Foundation

/// Explicit, in-memory startup fixtures. These never read or install library records.
@MainActor
enum SumiLibraryLaunchFixture {
    static func makeStoreIfRequested() -> SumiLibraryStore? {
        let arguments = ProcessInfo.processInfo.arguments
        let loading = arguments.contains("--sumi-library-loading-check")
        let empty = arguments.contains("--sumi-library-empty-check")
        let populated = arguments.contains("--sumi-library-populated-check")
        let delayed = arguments.contains("--sumi-library-delayed-check")
        let failed = arguments.contains("--sumi-library-error-check")
        guard loading || empty || populated || delayed || failed else { return nil }
        return SumiLibraryStore(searchSourceLoader: { [] }, snapshotLoader: {
            if loading { try await Task.sleep(for: .seconds(86_400)) }
            if delayed { try await Task.sleep(for: .seconds(6)) }
            if failed { throw URLError(.cannotLoadFromNetwork) }
            if empty { return SumiLibrarySnapshot(saved: [], recent: []) }
            var manga = try HonbakoTutorialManga.makeManga()
            manga.title = "Existing Library Book"
            return SumiLibrarySnapshot(saved: [SumiBook(manga: manga, isInLibrary: true)], recent: [])
        })
    }
}
#endif
