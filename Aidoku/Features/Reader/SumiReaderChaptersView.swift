#if SUMI
import AidokuRunner
import SwiftUI

struct SumiReaderChaptersView: View {
    let currentKey: String
    let source: AidokuRunner.Source?
    let manga: AidokuRunner.Manga?
    let languageSelection: ((String?, [AidokuRunner.Chapter]) -> Void)?
    let canRead: (AidokuRunner.Chapter) -> Bool
    let select: (AidokuRunner.Chapter, Bool) -> Void
    let close: () -> Void

    @State private var chapters: [AidokuRunner.Chapter]
    @State private var selectedLanguage: String
    @State private var loading = false
    @State private var committing = false
    @State private var errorMessage: String?
    @State private var languageNotice: String?
    @State private var retry = 0
    @State private var nativeTitleLanguages: [String] = []
    @State private var discoveringLanguages = false
    @State private var languageDiscoveryFailed = false
    @State private var languageDiscoveryRetry = 0

    init(chapters: [AidokuRunner.Chapter], currentKey: String,
         source: AidokuRunner.Source? = nil, manga: AidokuRunner.Manga? = nil,
         languageSelection: ((String?, [AidokuRunner.Chapter]) -> Void)? = nil,
         canRead: @escaping (AidokuRunner.Chapter) -> Bool,
         select: @escaping (AidokuRunner.Chapter, Bool) -> Void, close: @escaping () -> Void) {
        self.currentKey = currentKey
        self.source = source
        self.manga = manga
        self.languageSelection = languageSelection
        self.canRead = canRead
        self.select = select
        self.close = close
        var chapters = chapters
        if let source, source.languages.count == 1, let language = source.languages.first {
            chapters = chapters.map { chapter in
                var chapter = chapter
                chapter.language = chapter.language ?? language
                return chapter
            }
        }
        _chapters = State(initialValue: chapters)
        let preferred = manga.flatMap { SumiChapterLanguage.persistedLanguage(mangaID: $0.identifier) }
        _selectedLanguage = State(initialValue: SumiChapterLanguage.activeLanguage(chapters: chapters,
            currentChapter: chapters.first(where: { $0.key == currentKey }), preferred: preferred) ?? "")
        _discoveringLanguages = State(initialValue: source.map { $0.runner is HonbakoMangaDexRunner } == true && manga != nil)
    }

    private var languages: [String] {
        SumiLanguageChapterLoader.offeredLanguages(chapters: chapters, sourceKey: source?.key ?? "",
            advertisedLanguages: source?.languages ?? [], hasPackage: source?.url != nil,
            nativeTitleLanguages: nativeTitleLanguages)
    }

    private var visibleChapters: [AidokuRunner.Chapter] {
        Array(SumiChapterLanguage.filter(chapters, language: selectedLanguage).reversed())
    }

    private var currentChapter: AidokuRunner.Chapter? { chapters.first { $0.key == currentKey } }

    private var currentLanguage: String { SumiChapterLanguage.normalized(currentChapter?.language) ?? "" }

    var body: some View {
        NavigationStack {
            List {
                languageSection
                if let manga, let current = chapters.first(where: { $0.key == currentKey }) {
                    HonbakoReaderActionsView(manga: manga, chapter: current,
                        chapters: SumiChapterLanguage.filter(chapters, language: currentLanguage), sourceAvailable: source != nil)
                }
                if let languageNotice, !loading {
                    Section {
                        Text(languageNotice).foregroundStyle(.secondary)
                    }
                }
                if loading {
                    Section {
                        ProgressView("Finding Chapters in \(SourceLanguage.displayName(for: selectedLanguage))…")
                    }
                } else if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.secondary)
                        Button("Try Again") { retry += 1 }
                    }
                } else if visibleChapters.isEmpty {
                    ContentUnavailableView("No Chapters", systemImage: "book.closed",
                        description: Text("This source has no chapters in this language."))
                } else {
                    Section {
                        ForEach(visibleChapters, id: \.key) { chapter in
                            Button { Task { await choose(chapter, resumingTranslation: false) } } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(chapter.chapterNumber.map { "Chapter \(String(format: "%g", Double($0)))" } ?? chapter.title ?? "Chapter")
                                            .foregroundStyle(.primary)
                                        if chapter.chapterNumber != nil, let title = chapter.title, !title.isEmpty {
                                            Text(title).font(.subheadline).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if !canRead(chapter) { Image(systemName: "lock").foregroundStyle(.secondary) }
                                    else if chapter.key == currentKey { Image(systemName: "checkmark").foregroundStyle(.primary) }
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .disabled(!canRead(chapter) || committing)
                            .accessibilityIdentifier("Sumi.Reader.Chapter.\(chapter.key)")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .accessibilityIdentifier("Sumi.Reader.Chapters")
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(uiColor: .systemGroupedBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", systemImage: "xmark", action: close).disabled(committing)
                }
            }
            .task(id: "\(selectedLanguage)|\(retry)") { await loadLanguage() }
            .task(id: languageDiscoveryRetry) { await loadAvailableLanguages() }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .presentationBackground(Color(uiColor: .systemGroupedBackground))
        .tint(.primary)
        .interactiveDismissDisabled(committing)
    }

    private var languageSection: some View {
        Section {
            if languages.count > 1 || (languages.count == 1 && selectedLanguage.isEmpty) {
                Picker("Language", selection: $selectedLanguage) {
                    if selectedLanguage.isEmpty { Text("Original Edition").tag("") }
                    ForEach(languages, id: \.self) { code in
                        Text(SourceLanguage.displayName(for: code)).tag(code)
                    }
                }
                .pickerStyle(.navigationLink)
                .disabled(committing)
                .accessibilityIdentifier("Sumi.Reader.Language")
                .accessibilityHint("Continues the matching chapter in the selected language when available.")
            } else {
                LabeledContent("Language", value: languages.first.map(SourceLanguage.displayName(for:)) ?? "Original Edition")
                    .accessibilityIdentifier("Sumi.Reader.Language")
            }
            if discoveringLanguages {
                ProgressView("Finding Translations…")
            } else if languageDiscoveryFailed {
                Button("Check Other Languages Again") { languageDiscoveryRetry += 1 }
            }
        } header: {
            Text("Reading Language")
        } footer: {
            if discoveringLanguages {
                Text("Checking the languages available for this title.")
            } else if languageDiscoveryFailed {
                Text("Other translations couldn’t be checked. Your current chapters are still available.")
            } else if source?.runner is HonbakoMangaDexRunner {
                Text("Languages reported for this title. Chapter coverage may vary; your place is saved when you switch.")
            } else if source == nil {
                Text("Languages available in your downloaded chapters.")
            } else if languages.count > 1 {
                Text("Translations are provided by the source; availability varies by title. Your place is saved when you switch.")
            } else {
                Text("This source hasn’t provided other languages for this title.")
            }
        }
    }

    private func loadAvailableLanguages() async {
        guard let manga, let native = source?.runner as? HonbakoMangaDexRunner else { return }
        discoveringLanguages = true
        languageDiscoveryFailed = false
        do {
            let languages = try await native.availableLanguages(for: manga)
            try Task.checkCancellation()
            nativeTitleLanguages = languages
            discoveringLanguages = false
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled else { return }
            languageDiscoveryFailed = true
            discoveringLanguages = false
        }
    }

    private func loadLanguage() async {
        errorMessage = nil
        languageNotice = nil
        loading = false
        let language = selectedLanguage
        guard !language.isEmpty else { return }
        do {
            let missingEquivalent = language != currentLanguage && currentChapter.map {
                SumiChapterLanguage.equivalent(to: $0, in: chapters, language: language) == nil
            } == true
            if visibleChapters.isEmpty || missingEquivalent, let source, let manga, SumiLanguageChapterLoader.supports(source) {
                loading = true
                let fetched = try await SumiLanguageChapterLoader.load(source: source, manga: manga, language: language)
                try Task.checkCancellation()
                guard selectedLanguage == language else { return }
                chapters = SumiChapterLanguage.merge(chapters, with: fetched)
            }
            try Task.checkCancellation()
            guard selectedLanguage == language else { return }
            loading = false
            guard language != currentLanguage, let currentChapter, !visibleChapters.isEmpty else { return }
            let readable = chapters.filter(canRead)
            if let translated = SumiChapterLanguage.equivalent(to: currentChapter, in: readable, language: language) {
                await choose(translated, resumingTranslation: true)
            } else {
                languageNotice = "Your current chapter isn’t available in \(SourceLanguage.displayName(for: language)). Choose a chapter below to continue."
            }
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled, selectedLanguage == language else { return }
            errorMessage = "Chapters couldn’t be loaded. \(error.localizedDescription)"
            loading = false
        }
    }

    private func choose(_ chapter: AidokuRunner.Chapter, resumingTranslation: Bool) async {
        guard !committing else { return }
        committing = true
        defer { committing = false }
        do {
            let language = SumiChapterLanguage.normalized(selectedLanguage) ?? SumiChapterLanguage.normalized(chapter.language)
            if let manga { try await SumiChapterLanguage.persist(language: language, chapters: chapters, manga: manga) }
            try Task.checkCancellation()
            languageSelection?(language, chapters)
            select(chapter, resumingTranslation)
        } catch is CancellationError { }
        catch {
            errorMessage = "Your language choice couldn’t be saved. Try again."
        }
    }
}
#endif
