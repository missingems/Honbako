#if SUMI
import AidokuRunner
import SwiftUI

struct SumiReaderChaptersView: View {
    let currentKey: String
    let source: AidokuRunner.Source?
    let manga: AidokuRunner.Manga?
    let languageSelection: ((String?, [AidokuRunner.Chapter]) -> Void)?
    let canRead: (AidokuRunner.Chapter) -> Bool
    let select: (AidokuRunner.Chapter) -> Void
    let close: () -> Void

    @State private var chapters: [AidokuRunner.Chapter]
    @State private var selectedLanguage: String
    @State private var loading = false
    @State private var committing = false
    @State private var errorMessage: String?
    @State private var retry = 0

    init(chapters: [AidokuRunner.Chapter], currentKey: String,
         source: AidokuRunner.Source? = nil, manga: AidokuRunner.Manga? = nil,
         languageSelection: ((String?, [AidokuRunner.Chapter]) -> Void)? = nil,
         canRead: @escaping (AidokuRunner.Chapter) -> Bool,
         select: @escaping (AidokuRunner.Chapter) -> Void, close: @escaping () -> Void) {
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
    }

    private var languages: [String] {
        var values = SumiChapterLanguage.languages(in: chapters)
        if let source, SumiLanguageChapterLoader.supports(source) {
            values += source.languages.compactMap { SumiChapterLanguage.normalized($0) }
        }
        return Array(Set(values)).sorted {
            SourceLanguage.displayName(for: $0).localizedStandardCompare(SourceLanguage.displayName(for: $1)) == .orderedAscending
        }
    }

    private var visibleChapters: [AidokuRunner.Chapter] {
        Array(SumiChapterLanguage.filter(chapters, language: selectedLanguage).reversed())
    }

    var body: some View {
        NavigationStack {
            List {
                if let manga, let current = chapters.first(where: { $0.key == currentKey }) {
                    HonbakoReaderActionsView(manga: manga, chapter: current,
                        chapters: SumiChapterLanguage.filter(chapters, language: selectedLanguage), sourceAvailable: source != nil)
                }
                if !languages.isEmpty {
                    Section {
                        Picker("Language", selection: $selectedLanguage) {
                            if selectedLanguage.isEmpty { Text("Current Edition").tag("") }
                            ForEach(languages, id: \.self) { code in
                                Text(SourceLanguage.displayName(for: code)).tag(code)
                            }
                        }
                        .disabled(committing)
                        .accessibilityIdentifier("Sumi.Reader.Language")
                    }
                }
                if loading {
                    Section { ProgressView("Loading chapters…") }
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
                            Button { choose(chapter) } label: {
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
            .accessibilityIdentifier("Sumi.Reader.Chapters")
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", systemImage: "xmark", action: close).disabled(committing)
                }
            }
            .task(id: "\(selectedLanguage)|\(retry)") { await loadLanguage() }
        }
        .tint(.primary)
        .interactiveDismissDisabled(committing)
    }

    private func loadLanguage() async {
        errorMessage = nil
        loading = false
        guard !selectedLanguage.isEmpty, visibleChapters.isEmpty,
              let source, let manga, SumiLanguageChapterLoader.supports(source) else { return }
        let language = selectedLanguage
        loading = true
        do {
            let fetched = try await SumiLanguageChapterLoader.load(source: source, manga: manga, language: language)
            try Task.checkCancellation()
            guard selectedLanguage == language else { return }
            chapters = SumiChapterLanguage.merge(chapters, with: fetched)
            loading = false
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled, selectedLanguage == language else { return }
            errorMessage = "Chapters couldn’t be loaded. \(error.localizedDescription)"
            loading = false
        }
    }

    private func choose(_ chapter: AidokuRunner.Chapter) {
        guard !committing else { return }
        committing = true
        Task {
            do {
                let language = SumiChapterLanguage.normalized(selectedLanguage) ?? SumiChapterLanguage.normalized(chapter.language)
                if let manga { try await SumiChapterLanguage.persist(language: language, chapters: chapters, manga: manga) }
                languageSelection?(language, chapters)
                select(chapter)
            } catch {
                errorMessage = "Your language choice couldn’t be saved. Try again."
            }
            committing = false
        }
    }
}
#endif
