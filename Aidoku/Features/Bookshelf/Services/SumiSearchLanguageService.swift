#if SUMI
import CoreData
import Foundation

/// Snapshot helper for chapter metadata already stored on this device.
actor SumiSearchLanguageService {
    struct Context: Sendable {
        let chapterLanguages: [String]
        let sourceLanguages: [String]
    }

    static let shared = SumiSearchLanguageService()
    private var providerTask: Task<[String: [String]], Never>?

    func context(for id: MangaIdentifier) async -> Context {
        async let chapterLanguages = CoreDataManager.shared.container.performBackgroundTask { context in
            let request = NSFetchRequest<NSDictionary>(entityName: "Chapter")
            request.resultType = .dictionaryResultType
            request.propertiesToFetch = ["lang"]
            request.returnsDistinctResults = true
            request.predicate = NSPredicate(format: "mangaId == %@ AND sourceId == %@", id.mangaKey, id.sourceKey)
            return (try? context.fetch(request))?.compactMap { $0["lang"] as? String } ?? []
        }
        let providers = await providerLanguages()
        return await Context(chapterLanguages: chapterLanguages, sourceLanguages: providers[id.sourceKey] ?? [])
    }

    private func providerLanguages() async -> [String: [String]] {
        if let providerTask { return await providerTask.value }
        // Coalesce visible rows without retaining a stale snapshot after source setup.
        let task = Task {
            let infos = await SourceManager.shared.getSourceInfos()
            return Dictionary(infos.map { ($0.sourceId, $0.languages) }, uniquingKeysWith: { first, _ in first })
        }
        providerTask = task
        let result = await task.value
        providerTask = nil
        return result
    }
}
#endif
