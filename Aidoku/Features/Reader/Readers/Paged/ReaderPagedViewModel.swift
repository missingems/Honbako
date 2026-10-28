//
//  ReaderPagedViewModel.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import Foundation
import AidokuRunner

@MainActor
class ReaderPagedViewModel {
    let source: AidokuRunner.Source?
    let manga: AidokuRunner.Manga
    let temporaryPageStore: ReaderTemporaryPageStore?

    var chapter: AidokuRunner.Chapter?
    var pages: [Page] = []

    var preloadedChapter: AidokuRunner.Chapter?
    var preloadedPages: [Page] = []
    #if SUMI
    private var sumiLoadGeneration = 0
    private var sumiPreloadGeneration = 0
    private var sumiPreloadTarget: String?
    private var sumiPreloadTask: Task<[Page], Never>?
    #if DEBUG
    var sumiPageLoaderOverride: ((AidokuRunner.Chapter) async -> [Page])?
    #endif
    #endif

    init(
        source: AidokuRunner.Source?,
        manga: AidokuRunner.Manga,
        temporaryPageStore: ReaderTemporaryPageStore? = nil
    ) {
        self.source = source
        self.manga = manga
        self.temporaryPageStore = temporaryPageStore
    }

    #if SUMI
    @discardableResult
    func loadPages(chapter: AidokuRunner.Chapter) async -> Bool {
        guard !Task.isCancelled else { return false }
        sumiLoadGeneration += 1
        let generation = sumiLoadGeneration
        // An actual next-chapter open joins its in-flight preparation rather
        // than asking the source for the same chapter a second time.
        if sumiPreloadTarget == chapter.id, let task = sumiPreloadTask { _ = await task.value }
        guard generation == sumiLoadGeneration, !Task.isCancelled else { return false }
        sumiCancelPreload(except: chapter)
        if preloadedChapter?.id == chapter.id, !preloadedPages.isEmpty {
            self.chapter = chapter
            pages = preloadedPages
            preloadedPages = []
            preloadedChapter = nil
            return true
        }
        let previousChapter = self.chapter
        let previousPages = pages
        let loadedPages = await getPages(chapter: chapter, forceRefresh: previousChapter?.id == chapter.id)
        guard generation == sumiLoadGeneration, !Task.isCancelled else { return false }
        if let previousChapter, !previousPages.isEmpty {
            preloadedChapter = previousChapter
            preloadedPages = previousPages
        }
        self.chapter = chapter
        pages = loadedPages
        return true
    }
    #else
    func loadPages(chapter: AidokuRunner.Chapter) async {
        if preloadedChapter == chapter {
            pages = preloadedPages
            preloadedPages = []
            preloadedChapter = nil
        } else {
            if !pages.isEmpty {
                preloadedChapter = chapter
                preloadedPages = pages
            }
            self.chapter = chapter
            pages = await getPages(chapter: chapter)
        }
    }

    #endif

    @discardableResult
    func preload(chapter: AidokuRunner.Chapter) async -> [Page] {
        #if SUMI
        if preloadedChapter?.id == chapter.id, !preloadedPages.isEmpty { return preloadedPages }
        if sumiPreloadTarget == chapter.id, let task = sumiPreloadTask { return await task.value }
        sumiCancelPreload()
        let generation = sumiPreloadGeneration
        sumiPreloadTarget = chapter.id
        let task = Task { [weak self] () -> [Page] in
            guard let self, !Task.isCancelled else { return [] }
            let pages = await self.getPages(chapter: chapter)
            guard !Task.isCancelled, generation == self.sumiPreloadGeneration,
                  self.sumiPreloadTarget == chapter.id, !pages.isEmpty else { return [] }
            self.preloadedPages = pages
            self.preloadedChapter = chapter
            return pages
        }
        sumiPreloadTask = task
        let result = await task.value
        if generation == sumiPreloadGeneration {
            sumiPreloadTask = nil
            sumiPreloadTarget = nil
        }
        return result
        #else
        guard preloadedChapter != chapter else { return preloadedPages }
        preloadedChapter = nil
        let pages = await getPages(chapter: chapter)
        preloadedPages = pages
        preloadedChapter = chapter
        return pages
        #endif
    }

    #if SUMI
    func sumiCancelLoading() {
        sumiLoadGeneration += 1
        sumiCancelPreload()
    }

    /// Only one neighboring chapter is prepared. Advancing into that exact
    /// chapter retains its request; jumping elsewhere or closing cancels it.
    func sumiCancelPreload(except chapter: AidokuRunner.Chapter? = nil) {
        if let chapter, sumiPreloadTarget == chapter.id { return }
        sumiPreloadGeneration += 1
        sumiPreloadTask?.cancel()
        sumiPreloadTask = nil
        sumiPreloadTarget = nil
        if chapter == nil || preloadedChapter?.id != chapter?.id {
            preloadedChapter = nil
            preloadedPages = []
        }
    }
    #endif

    private func getPages(chapter: AidokuRunner.Chapter, forceRefresh: Bool = false) async -> [Page] {
#if SUMI && DEBUG
        if let sumiPageLoaderOverride { return await sumiPageLoaderOverride(chapter) }
        if let generated = SumiGridPreviewFixtures.generatedPages(manga: manga, chapter: chapter) { return generated }
#endif
        let sourceId = source?.key ?? manga.sourceKey
        let identifier = ChapterIdentifier(
            sourceKey: sourceId,
            mangaKey: manga.key,
            chapterKey: chapter.key
        )
        let language = chapter.language ?? source?.languages.first
        let isDownloaded = DownloadManager.shared.isChapterDownloaded(chapter: identifier)
        if isDownloaded {
            return await DownloadManager.shared.getDownloadedPages(for: identifier)
                .enumerated().map { ordinal, downloaded in
                    var page = downloaded.toOld(sourceId: sourceId, chapterId: chapter.key, language: language)
                    #if SUMI
                    page.index = ordinal
                    #endif
                    return page
                }
        } else {
            guard let source else { return [] }
            let fetched: [AidokuRunner.Page]?
            #if SUMI
            let cacheKey = SumiChapterPageListCache.Key(source: source, manga: manga, chapter: chapter)
            fetched = try? await SumiChapterPageListCache.shared.pages(for: cacheKey, source: source,
                forceRefresh: forceRefresh) { [source, manga, chapter] in
                    try await source.getPageList(manga: manga, chapter: chapter)
                }
            #else
            fetched = try? await source.getPageList(manga: manga, chapter: chapter)
            #endif
            guard var sourcePages = fetched else {
                return []
            }

            var pages: [Page] = []
            pages.reserveCapacity(sourcePages.count)

            // iterate in reverse so pages with image data are dropped
            while let sourcePage = sourcePages.popLast() {
                #if SUMI
                guard !Task.isCancelled else { return [] }
                #endif
                var page = sourcePage.toOld(
                    sourceId: sourceId,
                    chapterId: chapter.key,
                    language: language
                )
                #if SUMI
                page.index = sourcePages.count
                #endif
                if
                    let temporaryPageStore,
                    let image = page.image,
                    let fileURL = await temporaryPageStore.store(
                        image,
                        chapterKey: chapter.key,
                        pageIndex: sourcePages.count
                    )
                {
                    page.image = nil
                    page.imageURL = fileURL.absoluteString
                }
                pages.append(page)
            }

            return pages.reversed()
        }
    }
}
