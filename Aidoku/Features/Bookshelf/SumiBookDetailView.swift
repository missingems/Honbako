#if SUMI
import SwiftUI

struct SumiBookDetailView: View {
    @State private var book: SumiBook
    @ObservedObject var store: SumiLibraryStore
    @State private var chapters: [SumiChapterSnapshot] = []
    @State private var isLoadingChapters = true
    @State private var reader: SumiReaderSelection?
    @State private var isOpening = false
    @State private var isUpdatingLibrary = false
    @State private var chapterLoadGeneration = 0
    @State private var openingChapterID: ChapterIdentifier?
    @State private var readingError: String?
    @State private var openingTask: Task<Void, Never>?
    @State private var reloadTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(book: SumiBook, store: SumiLibraryStore) {
        _book = State(initialValue: book)
        self.store = store
    }

    private var isSaved: Bool { store.library.contains { $0.id == book.id } }
    private var isBusy: Bool { isOpening || isUpdatingLibrary }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if #available(iOS 27.1, *), geometry.size.width > geometry.size.height {
                    ArrangementView {
                        ScrollView { overview }
                    } secondary: {
                        List { chapterSection }
                            .listStyle(.insetGrouped)
                            .scrollContentBackground(.hidden)
                    }
                    .arrangementViewStyle(.split.axes(.horizontal))
                } else {
                    // A single scroll keeps the expanded book and every chapter
                    // reachable on the outer display and narrow app windows.
                    List {
                        Section { overview }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        chapterSection
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            Group {
                if reduceTransparency {
                    Color(uiColor: .systemBackground)
                } else {
                    Rectangle().fill(.ultraThinMaterial)
                }
            }
            .ignoresSafeArea()
        }
        .task { await loadDetails() }
        .onReceive(store.$library, perform: updateReadingState)
        .onReceive(NotificationCenter.default.publisher(for: .updateHistory)) { _ in
            if reader == nil && !isLoadingChapters { reloadChapters() }
        }
        .onDisappear(perform: cancelPendingWork)
        .fullScreenCover(item: $reader, onDismiss: readerClosed) { selection in
            SwiftUIReaderNavigationController(source: selection.source, manga: selection.manga,
                                             chapter: selection.chapter, startPage: selection.startPage)
                .ignoresSafeArea()
        }
    }

    private var overview: some View {
        SumiBookOverviewView(
            book: book, isSaved: isSaved, isOpening: isOpening, isUpdatingLibrary: isUpdatingLibrary,
            hasUnfinishedBookmark: book.hasUnfinishedBookmark,
            error: readingError, openReader: openReader, toggleLibrary: toggleLibrary
        )
    }

    private var chapterSection: some View {
        SumiChaptersSection(
            chapters: chapters, isLoading: isLoadingChapters, isOpening: isBusy,
            openingChapterID: openingChapterID, error: readingError,
            openChapter: openChapter, reload: reloadDetails
        )
    }

    private func loadDetails() async {
        chapterLoadGeneration += 1
        let generation = chapterLoadGeneration
        isLoadingChapters = true
        defer { if generation == chapterLoadGeneration { isLoadingChapters = false } }
        let updated = await store.fetchDetails(for: book)
        guard !Task.isCancelled, generation == chapterLoadGeneration else { return }
        book = updated
        let loaded = await store.chapterSnapshots(for: updated)
        guard !Task.isCancelled, generation == chapterLoadGeneration else { return }
        chapters = loaded
    }

    private func reloadDetails() {
        readingError = nil
        reloadTask?.cancel()
        reloadTask = Task { await loadDetails() }
    }

    private func reloadChapters() {
        chapterLoadGeneration += 1
        let generation = chapterLoadGeneration
        reloadTask?.cancel()
        reloadTask = Task {
            let loaded = await store.chapterSnapshots(for: book)
            guard !Task.isCancelled, generation == chapterLoadGeneration else { return }
            chapters = loaded
        }
    }

    private func updateReadingState(_ books: [SumiBook]) {
        guard let saved = books.first(where: { $0.id == book.id }) else { return }
        // Keep the loaded description and chapters while updating progress. A
        // library refresh can contain a smaller metadata snapshot.
        book = SumiBook(manga: book.manga, chapterLabel: saved.chapterLabel,
                        pageLabel: saved.pageLabel, progress: saved.progress,
                        isInLibrary: true, lastRead: saved.lastRead, bookmark: saved.bookmark)
    }

    private func readerClosed() {
        chapterLoadGeneration += 1
        let generation = chapterLoadGeneration
        isLoadingChapters = true
        reloadTask?.cancel()
        reloadTask = Task {
            defer { if generation == chapterLoadGeneration { isLoadingChapters = false } }
            await store.refresh()
            guard !Task.isCancelled, generation == chapterLoadGeneration else { return }
            updateReadingState(store.library)
            let loaded = await store.chapterSnapshots(for: book)
            guard !Task.isCancelled, generation == chapterLoadGeneration else { return }
            chapters = loaded
        }
    }

    private func openReader() {
        guard !isBusy else { return }
        isOpening = true
        readingError = nil
        openingChapterID = nil
        let selectedBook = book
        let opensBookmark = selectedBook.hasUnfinishedBookmark
        openingTask = Task {
            defer { isOpening = false; openingChapterID = nil }
            let selection: SumiReaderSelection?
            if opensBookmark { selection = await store.openBookmark(book: selectedBook) }
            else { selection = await store.resume(book: selectedBook) }
            guard let selection, !Task.isCancelled else {
                if !Task.isCancelled { readingError = store.errorMessage ?? "No readable chapters are available." }
                return
            }
            if !isSaved { await store.add(book: book) }
            guard !Task.isCancelled else { return }
            reader = selection
        }
    }

    private func openChapter(_ chapter: SumiChapterSnapshot) {
        guard !isBusy, chapter.canRead else { return }
        isOpening = true
        readingError = nil
        openingChapterID = chapter.id
        openingTask = Task {
            defer { isOpening = false; openingChapterID = nil }
            guard let selection = await store.selectChapter(book: book, chapter: chapter.chapter), !Task.isCancelled else {
                if !Task.isCancelled { readingError = store.errorMessage ?? "This chapter couldn’t be opened." }
                return
            }
            reader = selection
        }
    }

    private func toggleLibrary() {
        guard !isBusy else { return }
        isUpdatingLibrary = true
        openingTask = Task {
            defer { isUpdatingLibrary = false }
            if isSaved { await store.remove(book: book) }
            else { await store.add(book: book) }
        }
    }

    private func cancelPendingWork() {
        openingTask?.cancel()
        reloadTask?.cancel()
    }
}
#endif
