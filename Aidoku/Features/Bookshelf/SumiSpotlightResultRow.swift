#if SUMI
import SwiftUI

struct SumiSpotlightResultRow: View {
    private static let rowInset: CGFloat = 8
    private static let coverSpacing: CGFloat = 14

    let book: SumiBook
    let isLifted: Bool
    let isInLibrary: Bool
    let isSearchActive: Bool
    let editions: [SumiBook]
    let sourceName: (String) -> String
    let openBook: (SumiBook, SumiBookTransitionSource?) -> Void
    let addBook: (SumiBook) async -> Void
    var showsDivider = false
    @State private var anchor = SumiBookSourceAnchor()
    @State private var adding = false
    @State private var metadata: SumiSearchMetadataService.Metadata?
    @State private var metadataBookID: MangaIdentifier?
    @State private var languageContext: SumiSearchLanguageService.Context?
    @State private var presentedLanguages: SumiSearchLanguageInfo?
    @ScaledMetric(relativeTo: .body) private var coverScale: CGFloat = 1
    @ScaledMetric(relativeTo: .body) private var rowContentHeight: CGFloat = 114
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var coverWidth: CGFloat { 68 * min(coverScale, 1.5) }
    private var coverHeight: CGFloat { 100 * min(coverScale, 1.5) }
    private var titleInset: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? Self.rowInset : Self.rowInset + coverWidth + Self.coverSpacing
    }

    private var presentation: SumiSearchResultPresentation {
        SumiSearchResultPresentation(book: book, isInLibrary: isInLibrary,
            releaseYear: enrichedMetadata?.releaseYear, publishingStatus: enrichedMetadata?.publishingStatus)
    }
    private var enrichedMetadata: SumiSearchMetadataService.Metadata? {
        metadataBookID == book.id ? metadata : nil
    }
    private var author: String? {
        if let author = book.author { return author }
        let authors = enrichedMetadata?.authors ?? []
        return authors.isEmpty ? nil : authors.joined(separator: ", ")
    }
    private var languages: SumiSearchLanguageInfo? {
        guard metadataBookID == book.id else { return nil }
        return SumiSearchLanguageInfo(chapterLanguages: languageContext?.chapterLanguages ?? [],
            translatedLanguages: enrichedMetadata?.translatedLanguages ?? [],
            sourceLanguages: languageContext?.sourceLanguages ?? [])
    }
    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        let bookLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Self.coverSpacing))
        layout {
            Button(action: selectBook) {
                bookLayout {
                    SumiGridBookRepresentable(book: book, anchor: anchor)
                        .frame(width: coverWidth, height: coverHeight)
                        .opacity(isLifted ? 0 : 1)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(book.title).font(.body)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        SumiSearchResultSubtitle(author: author, presentation: presentation, languages: languages)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, minHeight: rowContentHeight, alignment: .leading)
                .contentShape(.rect)
                .accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .contextMenu {
                if !isInLibrary { Button("Add to Library", action: getBook) }
                if let languages {
                    Button("Languages", systemImage: "character.bubble") { presentedLanguages = languages }
                }
                if editions.count > 1 {
                    ForEach(editions) { edition in
                        Button(sourceName(edition.sourceKey)) { openBook(edition, nil) }
                    }
                }
            }
            .accessibilityRepresentation {
                Button(book.title, action: selectBook)
                    .accessibilityValue([presentation.publicationSubtitle, presentation.publicationBadge, author,
                        languages?.accessibilityText, presentation.readingPosition]
                        .compactMap { $0 }.joined(separator: ", "))
                    .accessibilityHint("Open manga")
                    .accessibilityIdentifier("Sumi.Search.Book.\(book.presentation.id)")
                    .accessibilityActions {
                        if !isInLibrary { Button("Add to Library", action: getBook) }
                        if let languages {
                            Button("Show Languages") { presentedLanguages = languages }
                        }
                        if editions.count > 1 {
                            ForEach(editions) { edition in
                                Button("Read from \(sourceName(edition.sourceKey))") { openBook(edition, nil) }
                            }
                        }
                    }
            }
            SumiSearchResultActionButton(action: presentation.action, readingPosition: presentation.readingPosition,
                bookTitle: book.title, bookID: book.presentation.id, adding: adding, perform: performAction)
        }
        .padding(Self.rowInset)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Divider().padding(.leading, titleInset)
                    .padding(.trailing, Self.rowInset)
            }
        }
        .contentShape(.rect(cornerRadius: 14))
        .popover(item: $presentedLanguages) { SumiSearchLanguageDetailsView(info: $0) }
        .task(id: isSearchActive ? book.id : nil) { await loadMetadata() }
    }

    private func loadMetadata() async {
        guard isSearchActive else { return }
        let id = book.id
        if metadataBookID != id { metadata = nil; languageContext = nil; metadataBookID = id }
        let context = await SumiSearchLanguageService.shared.context(for: id)
        guard !Task.isCancelled, metadataBookID == id else { return }
        withAnimation(.easeInOut(duration: reduceMotion ? 0 : 0.18)) { languageContext = context }
        guard let result = await SumiSearchMetadataService.shared.metadata(for: book),
              !Task.isCancelled, metadataBookID == id else { return }
        withAnimation(.easeInOut(duration: reduceMotion ? 0 : 0.18)) { metadata = result }
    }

    private func performAction() {
        if presentation.action == .get { getBook() }
        else { selectBook() }
    }

    private func getBook() {
        guard !adding, !isInLibrary else { return }
        adding = true
        Task { await addBook(book); adding = false }
    }

    private func selectBook() {
        let source = anchor.view.flatMap { SumiBookTransitionSource.capture($0, replacementView: { anchor.view }) }
        openBook(book, source)
    }
}
#endif
