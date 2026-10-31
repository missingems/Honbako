#if SUMI
import Foundation

@MainActor
enum HonbakoAutomationSources {
    typealias Models = HonbakoAutomationManagement

    static func catalog(offset: Int, limit: Int) async -> Models.Catalog {
        let manager = SourceManager.shared
        await manager.waitForSourceListsLoad()
        let installed = await manager.getSourceInfos()
        let lists = await manager.getLoadedSourceLists()
        let urls = await manager.getSourceListURLs().sorted { $0.absoluteString < $1.absoluteString }
        var all: [String: Models.CatalogSource] = [:]
        for info in installed where safeID(info.sourceId) {
            all[info.sourceId] = .init(sourceId: info.sourceId, name: String(info.name.prefix(500)), installed: true, disabled: info.disabled,
                repositoryURL: info.externalInfo?.sourceUrl.flatMap(safeURL))
        }
        for list in lists.values.sorted(by: { $0.url.absoluteString < $1.url.absoluteString }) {
            for info in list.sources where safeID(info.id) && all[info.id] == nil {
                all[info.id] = .init(sourceId: info.id, name: String(info.name.prefix(500)), installed: false, disabled: false, repositoryURL: safeURL(list.url))
            }
        }
        let ordered = all.values.sorted { $0.sourceId < $1.sourceId }
        let page = Array(ordered.dropFirst(offset).prefix(limit))
        let repositories = urls.compactMap { url -> Models.Repository? in
            guard let safe = safeURL(url) else { return nil }
            return .init(url: safe, name: String((lists[url]?.name ?? url.host ?? "Repository").prefix(500)), available: lists[url] != nil)
        }
        return .init(sources: page, repositories: Array(repositories.prefix(100)),
            nextOffset: offset + page.count < ordered.count ? offset + page.count : nil, observedAt: Date.now.ISO8601Format())
    }

    /// Preparation never fetches a new repository or installs code. It resolves
    /// existing IDs locally so the phone can show exactly what will change.
    static func review(_ change: Models.Change) async throws -> String {
        try change.validate()
        #if !HONBAKO_EXTERNAL_SOURCES
        // This build can't fetch or install extension code, so it never asks
        // the person to approve a change that could only fail.
        guard !["install", "add_repository", "refresh_repositories"].contains(change.action) else {
            throw HonbakoAutomationPolicy.Failure.invalidJob
        }
        #endif
        let manager = SourceManager.shared
        if let id = change.sourceId {
            let installed = await manager.getSourceInfos()
            if let source = installed.first(where: { $0.sourceId == id }) { return source.name }
            guard change.action == "install" else { throw HonbakoAutomationPolicy.Failure.invalidJob }
            let lists = await manager.getLoadedSourceLists()
            guard let info = lists.values.flatMap(\.sources).first(where: { $0.id == id }) else { throw HonbakoAutomationPolicy.Failure.invalidJob }
            return info.name
        }
        if change.action == "remove_repository" {
            guard let text = change.repositoryURL, let url = Models.Change.safeRepository(text),
                  await manager.getSourceListURLs().contains(url) else { throw HonbakoAutomationPolicy.Failure.invalidJob }
        }
        return change.repositoryURL ?? "Configured extension repositories"
    }

    static func apply(_ change: Models.Change) async throws -> Models.Result {
        try change.validate()
        let manager = SourceManager.shared
        switch change.action {
        case "install":
            guard let id = change.sourceId else { throw HonbakoAutomationPolicy.Failure.invalidJob }
            let installed = await manager.getSourceInfos()
            if !installed.contains(where: { $0.sourceId == id }) {
                let lists = await manager.getLoadedSourceLists()
                guard let info = lists.values.flatMap(\.sources).filter({ $0.id == id }).max(by: { $0.version < $1.version }),
                      await manager.installExternalSource(info)?.id == id else { throw HonbakoAutomationPolicy.Failure.invalidJob }
            }
        case "enable", "disable", "remove":
            guard let id = change.sourceId else { throw HonbakoAutomationPolicy.Failure.invalidJob }
            if change.action == "enable" { await manager.enable(sourceKey: id) }
            else if change.action == "disable" { await manager.disable(sourceKey: id) }
            else { await manager.remove(sourceKey: id) }
            let installed = await manager.getSourceInfos()
            let source = installed.first { $0.sourceId == id }
            let applied = change.action == "remove" ? source == nil : source?.disabled == (change.action == "disable")
            guard applied else { throw HonbakoAutomationPolicy.Failure.invalidJob }
        case "add_repository", "remove_repository":
            guard let text = change.repositoryURL, let url = Models.Change.safeRepository(text) else { throw HonbakoAutomationPolicy.Failure.invalidJob }
            if change.action == "add_repository" {
                if !(await manager.getSourceListURLs().contains(url)) {
                    guard await manager.addSourceList(url: url) else { throw HonbakoAutomationPolicy.Failure.invalidJob }
                }
            } else { await manager.removeSourceList(url: url) }
        case "refresh_repositories":
            await manager.startSourceListsReload()
            await manager.waitForSourceListsLoad()
            guard await manager.getMissingSourceLists().isEmpty else { throw HonbakoAutomationPolicy.Failure.invalidJob }
        default: throw HonbakoAutomationPolicy.Failure.invalidJob
        }
        return .init(change: change, observedAt: Date.now.ISO8601Format())
    }

    private static func safeID(_ value: String) -> Bool {
        HonbakoAutomationPolicy.validItem(.init(sourceId: value, mangaId: "source"))
    }
    private static func safeURL(_ url: URL) -> String? {
        Models.Change.safeRepository(url.absoluteString)?.absoluteString
    }
}
#endif
