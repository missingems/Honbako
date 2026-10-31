#if HONBAKO_EXTERNAL_SOURCES && targetEnvironment(simulator)
@testable import Sumi
import AidokuRunner
import Foundation
import Testing
import UIKit

/// Explicit opt-in for the disposable simulator only. Uses public metadata and
/// one page image in memory; never installs a source, creates a library record,
/// persists progress, shares through MCP or saves copyrighted page artwork.
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["HONBAKO_LIVE_MANGADEX_SANITY"] == "1"))
struct HonbakoLiveMangaDexSanityTests {
    @Test("Live JJK recovers from English external-only chapters into a real readable edition and decodes its first page")
    func jujutsuKaisenReadableEdition() async throws {
        let defaultsName = "Honbako.LiveMangaDex.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        defaults.set(["en"], forKey: HonbakoMangaDexRunner.sourceKey + ".languages")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let requests = Requests()
        let runner = HonbakoMangaDexRunner(defaults: defaults, transport: { request in
            await requests.recordMetadata(request)
            let (data, response) = try await session.data(for: request)
            let http = try #require(response as? HTTPURLResponse)
            return (data, http)
        })
        let manga = AidokuRunner.Manga(sourceKey: HonbakoMangaDexRunner.sourceKey,
            key: "c52b2ce3-7f95-469c-96b0-479524fb7a1a", title: "Jujutsu Kaisen", viewer: .rightToLeft)
        let english = try await runner.chapters(for: manga, language: "en")
        try #require(!english.isEmpty, "The live title changed; this test expects the reported English external-only case")
        let englishUnavailable = english.allSatisfy { $0.locked }
        try #require(englishUnavailable, "English availability changed; reassess the live scenario instead of assuming a regression")
        let defaultChoices = SumiReaderOpeningPolicy.candidates(history: nil, chaptersNewestFirst: english, canRead: { !$0.locked })
        let initial = try await SumiReadableOpeningResolver.resolve(defaultChoices, state: { _ in .unknown }) { _ in
            Issue.record("Locked external-only chapters must not request page manifests")
            return false
        }
        #expect(initial == nil)
        try #require(SumiAlternativeEditionOpening.mayRecover(explicitLanguage: nil, metadataFailed: false, candidateStates: []))
        let alternatives = try await runner.readableAlternativeChapters(for: manga)
        let plan = try #require(SumiAlternativeEditionOpening.plan(original: english, alternativesNewestFirst: alternatives,
            history: nil, explicitLanguage: nil, configuredLanguages: ["en"], deviceLanguages: ["en-US"]))
        var manifests: [String: [AidokuRunner.Page]] = [:]
        let candidate = try await SumiReadableOpeningResolver.resolve(plan.choices, state: { _ in .unknown }) { candidate in
            let chapter = try #require(plan.readableChapters.first { $0.key == candidate.chapterKey })
            let pages = try await runner.getPageList(manga: manga, chapter: chapter)
            manifests[chapter.key] = pages
            return !pages.isEmpty
        }
        let resolved = try #require(candidate)
        let selected = try #require(plan.readableChapters.first { $0.key == resolved.chapterKey })
        let language = try #require(SumiChapterLanguage.normalized(selected.language))
        #expect(language != "en")
        #expect(resolved.startPage == 1)
        #expect(selected.chapterNumber == 1, "Absent a preferred readable edition, recover to the earliest actual chapter")
        let merged = SumiChapterLanguage.merge(english, with: SumiChapterLanguage.filter(plan.readableChapters, language: language))
        #expect(Set(english.map(\.key)).isSubset(of: Set(merged.map(\.key))))
        let retainedUnavailable = merged.filter { $0.language == "en" }.allSatisfy { $0.locked }
        #expect(retainedUnavailable, "The same locked values drive disabled gray chapter-menu rows")
        #expect(defaults.stringArray(forKey: HonbakoMangaDexRunner.sourceKey + ".languages") == ["en"])

        // A unique, unregistered book identity makes the native title's optional
        // filter lookup read an absent record. Do not load the reader's view or
        // begin its reading lifecycle, which would record history.
        let displayManga = AidokuRunner.Manga(sourceKey: "honbako-live-sanity-\(UUID().uuidString)", key: manga.key,
            title: manga.title, viewer: manga.viewer, chapters: merged)
        let reader = ReaderViewController(source: nil, manga: displayManga, chapter: selected, startPage: resolved.startPage)
        reader.sumiAutomaticOpeningLanguage = language
        reader.loadNavbarTitle()
        if #available(iOS 26.0, *) {
            #expect(reader.navigationItem.subtitle == "Chapter 1 · \(SourceLanguage.displayName(for: language))")
        }
        #expect(!reader.isViewLoaded, "The probe must not start a reading session")

        let first = try #require(manifests[selected.key]?.first)
        guard case let .url(url, context) = first.content else {
            Issue.record("The native connector must return an HTTPS image page")
            return
        }
        let imageRequest = try await runner.getImageRequest(url: url.absoluteString, context: context)
        let (imageData, response) = try await session.data(for: imageRequest)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)
        #expect(http.mimeType?.hasPrefix("image/") == true)
        try #require(!imageData.isEmpty && imageData.count < 20 * 1024 * 1024)
        let image = try #require(UIImage(data: imageData))
        let decoded = try #require(image.preparingForDisplay())
        #expect(decoded.size.width > 0 && decoded.size.height > 0)
        #expect(decoded.cgImage != nil)
        #expect(await requests.alternativeFeeds == 1, "Recovery must issue only one bounded any-language feed")
        print("Live JJK: English unavailable=\(english.count), selected=\(language) chapter1 page1, first image HTTP\(http.statusCode), decoded=\(Int(decoded.size.width))x\(Int(decoded.size.height)); one image GET, no library/history writes")
    }

    private actor Requests {
        private(set) var alternativeFeeds = 0
        func recordMetadata(_ request: URLRequest) {
            guard let url = request.url, url.path.hasSuffix("/feed") else { return }
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if !query.contains(where: { $0.name == "translatedLanguage[]" }) { alternativeFeeds += 1 }
        }
    }
}
#endif
