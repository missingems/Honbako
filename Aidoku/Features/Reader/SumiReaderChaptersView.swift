#if SUMI
import AidokuRunner
import SwiftUI

struct SumiReaderChaptersView: View {
    let currentKey: String
    let currentPage: Int
    let currentTotalPages: Int
    let source: AidokuRunner.Source?
    let manga: AidokuRunner.Manga?
    let languageSelection: ((String?, [AidokuRunner.Chapter]) -> Void)?
    let setJapaneseLearning: ((Bool) -> Void)?
    private let offersJapaneseLearning: Bool
    @State private var japaneseLearningEnabled: Bool
    @ObservedObject private var pro = HonbakoProStore.shared
    let canRead: (AidokuRunner.Chapter) -> Bool
    let select: (AidokuRunner.Chapter, Bool) -> Void
    let close: () -> Void

    @StateObject private var chapterState = HonbakoReaderChapterState()
    @ObservedObject private var availability = HonbakoChapterAvailability.shared
    @State private var requestedPro: HonbakoProFeature?
    @State private var showingEarlierPrompt = false
    @State private var pendingChapter: AidokuRunner.Chapter?
    @State private var pendingEarlier: [AidokuRunner.Chapter] = []
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
    @State private var scrolledToCurrentChapter = false

    init(chapters: [AidokuRunner.Chapter], currentKey: String,
         currentPage: Int = 0, currentTotalPages: Int = 0,
         source: AidokuRunner.Source? = nil, manga: AidokuRunner.Manga? = nil,
         languageSelection: ((String?, [AidokuRunner.Chapter]) -> Void)? = nil,
         japaneseLearningEnabled: Bool? = nil, setJapaneseLearning: ((Bool) -> Void)? = nil,
         canRead: @escaping (AidokuRunner.Chapter) -> Bool,
         select: @escaping (AidokuRunner.Chapter, Bool) -> Void, close: @escaping () -> Void) {
        self.currentKey = currentKey
        self.currentPage = currentPage
        self.currentTotalPages = currentTotalPages
        self.source = source
        self.manga = manga
        self.languageSelection = languageSelection
        self.setJapaneseLearning = setJapaneseLearning
        offersJapaneseLearning = japaneseLearningEnabled != nil
        _japaneseLearningEnabled = State(initialValue: japaneseLearningEnabled ?? false)
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
        SumiChapterLanguage.filter(chapters, language: selectedLanguage)
    }

    private var currentChapter: AidokuRunner.Chapter? { chapters.first { $0.key == currentKey } }

    private var currentLanguage: String { SumiChapterLanguage.normalized(currentChapter?.language) ?? "" }

    private var currentScrollTarget: String? {
        !loading && visibleChapters.contains(where: { $0.key == currentKey }) ? currentKey : nil
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                List {
                    if let manga, HonbakoDeviceModel.isPhoneDuo {
                        Section {
                            HonbakoMangaCoverModeControl(mangaID: manga.identifier,
                                requestPro: { requestedPro = .coverDisplay })
                                .disabled(committing)
                        } footer: {
                            Text("Choose whether this manga appears on the outer display while you read. Cover mode requires Honbako Pro and uses the camera. No photos or video are recorded or saved.")
                        }
                    }
                    if offersJapaneseLearning {
                        Section {
                            Toggle("Romaji on Page", isOn: Binding(
                                get: { japaneseLearningEnabled && pro.hasPro && HonbakoProStore.cachedHasPro },
                                set: { enabled in
                                    guard !enabled || (pro.hasPro && HonbakoProStore.cachedHasPro) else { requestedPro = .japaneseGuide; return }
                                    japaneseLearningEnabled = enabled
                                    setJapaneseLearning?(enabled)
                                }
                            ))
                                .tint(Color(uiColor: .systemGreen))
                                .accessibilityIdentifier("Honbako.Reader.Japanese.ToggleInChapters")
                                .disabled(committing)
                                .onChange(of: pro.hasPro) { _, enabled in
                                    guard !enabled else { return }
                                    japaneseLearningEnabled = false
                                    setJapaneseLearning?(false)
                                }
                        } footer: {
                            Text("Read character-aligned romaji directly on the manga. Tap for pronunciation and translation.")
                        }
                    }
                    languageSection
                    if let manga, let current = chapters.first(where: { $0.key == currentKey }) {
                        HonbakoReaderActionsView(manga: manga, chapter: current,
                            chapters: SumiChapterLanguage.filter(chapters, language: currentLanguage), sourceAvailable: source != nil,
                            chapterState: chapterState, requestPro: { requestedPro = $0 })
                            .disabled(committing)
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
                                HStack(spacing: 12) {
                                    Button { Task { await choose(chapter, resumingTranslation: false) } } label: {
                                        chapterLabel(chapter)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!isReadable(chapter) || committing)
                                    .accessibilityIdentifier("Sumi.Reader.Chapter.\(chapter.key)")
                                    .accessibilityAddTraits(chapter.key == currentKey ? .isSelected : [])
                                    .accessibilityValue(confirmedUnavailable(chapter) ? String(localized: "Unavailable")
                                        : chapter.key == currentKey ? String(localized: "Currently reading") : "")
                                    if manga?.sourceKey != HonbakoTutorialManga.sourceKey { chapterDownloadMenu(chapter) }
                                }
                                .id(chapter.key)
                                .listRowBackground(chapter.key == currentKey
                                    ? HonbakoPalette.accent.opacity(0.16) : Color(uiColor: .secondarySystemGroupedBackground))
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
                .task(id: currentScrollTarget) {
                    guard let target = currentScrollTarget, !scrolledToCurrentChapter else { return }
                    // Wait for the native List to register the loaded row IDs.
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    scroll.scrollTo(target, anchor: .center)
                    scrolledToCurrentChapter = true
                }
                .task(id: "\(selectedLanguage)|\(retry)") { await loadLanguage() }
                .task(id: languageDiscoveryRetry) { await loadAvailableLanguages() }
                .task(id: chapters.map(\.key)) {
                    await chapterState.configure(manga: manga, chapters: chapters, currentKey: currentKey,
                        currentPage: currentPage, currentTotal: currentTotalPages)
                }
            }
        }
        // Present from the stable picker host, not a reusable List section.
        .sheet(item: $requestedPro) { feature in HonbakoProView(feature: feature) }
        .alert("Mark Earlier Chapters as Read?", isPresented: $showingEarlierPrompt, presenting: pendingChapter) { chapter in
            Button("Keep Unread", role: .cancel) { completeEarlierPrompt(chapter, markRead: false) }
            Button("Mark as Read") { completeEarlierPrompt(chapter, markRead: true) }
        } message: { _ in
            Text("There are \(pendingEarlier.count) earlier unread chapters in this language.")
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .presentationBackground(Color(uiColor: .systemGroupedBackground))
        .tint(HonbakoPalette.accent)
        .interactiveDismissDisabled(committing)
    }

    private func confirmedUnavailable(_ chapter: AidokuRunner.Chapter) -> Bool {
        if let manga {
            let id = ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: chapter.key)
            if DownloadManager.shared.getDownloadStatus(for: id) == .finished { return false }
            if let source, availability.isUnavailable(source: source, manga: manga, chapter: chapter) { return true }
        }
        return chapter.locked
    }

    private func isReadable(_ chapter: AidokuRunner.Chapter) -> Bool {
        canRead(chapter) && !confirmedUnavailable(chapter)
    }

    private func chapterLabel(_ chapter: AidokuRunner.Chapter) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(chapter.chapterNumber.map { String(localized: "Chapter \(String(format: "%g", Double($0)))") }
                    ?? chapter.title ?? String(localized: "Chapter"))
                    .foregroundStyle(confirmedUnavailable(chapter) ? Color.secondary : Color.primary)
                if chapter.chapterNumber != nil, let title = chapter.title, !title.isEmpty {
                    Text(title).font(.subheadline).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    if let date = chapter.dateUploaded {
                        Text(date, format: .dateTime.year().month(.abbreviated).day())
                            .accessibilityIdentifier("Honbako.Reader.Chapter.ReleaseDate.\(chapter.key)")
                    } else {
                        Text("Date Unavailable")
                            .accessibilityIdentifier("Honbako.Reader.Chapter.ReleaseDate.\(chapter.key)")
                    }
                    Text("·").accessibilityHidden(true)
                    Text(chapterState.reading[chapter.key]?.label ?? String(localized: "Unread"))
                        .accessibilityIdentifier("Honbako.Reader.Chapter.Progress.\(chapter.key)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !isReadable(chapter) { Image(systemName: "lock").foregroundStyle(.secondary) }
            else if chapter.key == currentKey { Image(systemName: "checkmark.circle.fill").foregroundStyle(HonbakoPalette.accent) }
            else if chapterState.reading[chapter.key]?.completed == true {
                Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
    }

    private func chapterDownloadMenu(_ chapter: AidokuRunner.Chapter) -> some View {
        let status = chapterState.statuses[chapter.key] ?? .none
        let active = status == .queued || status == .downloading || status == .paused
        return Menu {
            if active {
                Button("Cancel Download", systemImage: "xmark.circle") {
                    guard let manga else { return }
                    let id = ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: chapter.key)
                    Task { await DownloadManager.shared.cancelDownloads(for: [id]); await chapterState.refresh() }
                }
            } else if status == .finished {
                Button("Remove Download", systemImage: "trash", role: .destructive) {
                    guard let manga else { return }
                    let id = ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: chapter.key)
                    Task { await DownloadManager.shared.delete(chapters: [id]); await chapterState.refresh() }
                }
            } else {
                Button(status == .failed ? String(localized: "Retry Download") : String(localized: "Download Chapter"),
                       systemImage: status == .failed ? "arrow.clockwise" : "arrow.down.circle") {
                    downloadChapter(chapter)
                }
                .disabled(source == nil || chapter.locked || confirmedUnavailable(chapter))
            }
        } label: {
            VStack(spacing: 3) {
                if status == .downloading, let item = chapterState.downloads[chapter.key], item.total > 0 {
                    ProgressView(value: min(1, Double(item.progress) / Double(item.total)))
                        .progressViewStyle(.circular)
                    Text("\(item.progress)/\(item.total)").font(.caption)
                } else {
                    Image(systemName: status == .finished ? "checkmark.circle" : status == .failed ? "arrow.clockwise.circle"
                        : active ? "clock" : "arrow.down.circle")
                }
            }
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Offline Options")
        .accessibilityIdentifier("Honbako.Reader.Chapter.Download.\(chapter.key)")
        .disabled(committing)
    }

    private func downloadChapter(_ chapter: AidokuRunner.Chapter) {
        guard HonbakoProStore.shared.hasPro else { requestedPro = .offline; return }
        guard let manga else { return }
        var payload = manga
        payload.chapters = chapters
        Task { await DownloadManager.shared.download(manga: payload, chapters: [chapter]); await chapterState.refresh() }
    }

    private func completeEarlierPrompt(_ chapter: AidokuRunner.Chapter, markRead: Bool) {
        let earlier = pendingEarlier
        guard let manga else { return }
        HonbakoEarlierChapterPrompt.recordDecision(mangaID: manga.identifier, chapterKey: chapter.key)
        Task {
            if markRead { await HistoryManager.shared.addHistory(mangaId: manga.identifier, chapters: earlier) }
            await choose(chapter, resumingTranslation: false, considerEarlier: false)
        }
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
                LabeledContent("Language", value: languages.first.map(SourceLanguage.displayName(for:)) ?? String(localized: "Original Edition"))
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
                availability.clear(sourceKey: source.key, mangaKey: manga.key)
                chapters = SumiChapterLanguage.merge(chapters, with: fetched)
            }
            try Task.checkCancellation()
            guard selectedLanguage == language else { return }
            loading = false
            guard language != currentLanguage, let currentChapter, !visibleChapters.isEmpty else { return }
            let readable = chapters.filter(isReadable)
            if let translated = SumiChapterLanguage.equivalent(to: currentChapter, in: readable, language: language) {
                await choose(translated, resumingTranslation: true)
            } else {
                languageNotice = String(localized: "Your current chapter isn’t available in \(SourceLanguage.displayName(for: language)). Choose a chapter below to continue.")
            }
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled, selectedLanguage == language else { return }
            errorMessage = String(localized: "Chapters couldn’t be loaded. \(error.localizedDescription)")
            loading = false
        }
    }

    private func choose(_ chapter: AidokuRunner.Chapter, resumingTranslation: Bool,
                        considerEarlier: Bool = true) async {
        guard !committing, isReadable(chapter) else { return }
        committing = true
        defer { committing = false }
        do {
            if considerEarlier, !resumingTranslation, chapter.key != currentKey,
               !AppSettings.general.incognitoMode.get(), manga != nil {
                let completed = await chapterState.completedKeys()
                try Task.checkCancellation()
                let earlier = HonbakoEarlierChapterPolicy.unreadBefore(chapter, in: chapters, completedKeys: completed)
                if !earlier.isEmpty {
                    pendingChapter = chapter
                    pendingEarlier = earlier
                    showingEarlierPrompt = true
                    return
                }
            }
            let language = SumiChapterLanguage.normalized(selectedLanguage) ?? SumiChapterLanguage.normalized(chapter.language)
            if let manga { try await SumiChapterLanguage.persist(language: language, chapters: chapters, manga: manga) }
            try Task.checkCancellation()
            languageSelection?(language, chapters)
            select(chapter, resumingTranslation)
        } catch is CancellationError { }
        catch {
            errorMessage = String(localized: "Your language choice couldn’t be saved. Try again.")
        }
    }
}
#endif
