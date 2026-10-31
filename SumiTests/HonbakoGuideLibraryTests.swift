@testable import Sumi
import AidokuRunner
import CoreData
import Foundation
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct HonbakoGuideLibraryTests {
    @Test("Every original guide has four distinct offline pages in all four languages")
    func readableEditions() throws {
        var covers: Set<URL> = []
        for guide in HonbakoGuideBook.allCases {
            let manga = try HonbakoGuideLibrary.makeManga(guide)
            covers.insert(try #require(manga.cover.flatMap(URL.init(string:))))
            #expect(manga.viewer == .rightToLeft)
            let chapters = try #require(manga.chapters)
            #expect(chapters.count == 4)
            for chapter in chapters {
                let pages = try HonbakoGuideLibrary.pages(guide: guide, chapter: chapter)
                #expect(pages.count == 4)
                var contents: Set<Data> = []
                for page in pages {
                    guard case .url(let url, _) = page.content else { Issue.record("Expected local page"); continue }
                    #expect(url.isFileURL)
                    let data = try Data(contentsOf: url)
                    let image = try #require(UIImage(data: data))
                    #expect(image.size == CGSize(width: 1024, height: 1536))
                    contents.insert(data)
                }
                #expect(contents.count == 4)
            }
            #expect(throws: (any Error).self) { try HonbakoGuideLibrary.pages(guide: guide, chapter: .init(key: "../invalid")) }
        }
        #expect(covers.count == HonbakoGuideBook.allCases.count)
    }

    @Test("Guides seed once, stay removed after relaunch setup, and can be found and added again")
    func removalAndRecovery() async throws {
        let defaults = UserDefaults.standard
        let priorFlags = HonbakoGuideBook.allCases.map { defaults.object(forKey: $0.seedKey) }
        let ids = HonbakoGuideBook.allCases.map { MangaIdentifier(sourceKey: HonbakoTutorialManga.sourceKey, mangaKey: $0.rawValue) }
        for guide in HonbakoGuideBook.allCases { defaults.removeObject(forKey: guide.seedKey) }
        await HonbakoGuideLibrary.ensureInstalled()
        let initial = await membership(ids)
        #expect(initial == HonbakoGuideBook.allCases.map { _ in true })
        try await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.removeFromLibrary(ids: [ids[0]], context: context)
            try context.save()
        }
        await HonbakoGuideLibrary.ensureInstalled()
        #expect(await membership(ids) == ids.indices.map { $0 != 0 })
        let runner = HonbakoTutorialRunner()
        let title = try HonbakoGuideLibrary.makeManga(.find).title
        let found = try await runner.getSearchMangaList(query: title, page: 1, filters: [])
        let recovered = try #require(found.entries.first { $0.key == HonbakoGuideBook.find.rawValue })
        try await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.addToLibrary(manga: recovered, chapters: recovered.chapters ?? [], context: context)
            try context.save()
        }
        #expect(await membership(ids) == ids.map { _ in true })
        let next = try await runner.getSearchMangaList(query: title, page: 2, filters: [])
        #expect(next.entries.isEmpty)
        try await CoreDataManager.shared.container.performBackgroundTask { context in
            for id in ids { CoreDataManager.shared.removeManga(mangaId: id, context: context) }
            try context.save()
        }
        for (guide, value) in zip(HonbakoGuideBook.allCases, priorFlags) {
            defaults.set(value, forKey: guide.seedKey)
        }
    }

    @Test("Default search includes the bundled local catalog without installing an external provider")
    func defaultSearchFindsGuides() async throws {
        let key = HonbakoGuideLibrary.searchEnabledKey
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(true, forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }
        let store = SumiLibraryStore()
        let title = try HonbakoGuideLibrary.makeManga(.connect).title
        store.search(query: title)
        for _ in 0..<200 {
            if !store.isSearching { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(!store.isSearching)
        #expect(store.searchResults.contains { $0.manga.key == HonbakoGuideBook.connect.rawValue })
        store.cancelSearch()
    }

    private func membership(_ ids: [MangaIdentifier]) async -> [Bool] {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            ids.map { CoreDataManager.shared.hasLibraryManga(mangaId: $0, context: context) }
        }
    }
}
