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
    @State private var metadataHeight: CGFloat = 66
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var coverHeight: CGFloat { max(66, metadataHeight) }
    private var coverWidth: CGFloat { coverHeight * CGFloat(SumiGridBookPose.coverAspect) }

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
        layout {
            Button(action: selectBook) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title).font(.body).lineLimit(2)
                    SumiSearchResultSubtitle(author: author, presentation: presentation, languages: languages)
                }
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if abs(metadataHeight - height) > 0.5 { metadataHeight = height.rounded(.up) }
                }
                .padding(.leading, coverWidth + Self.coverSpacing)
                .frame(maxWidth: .infinity, minHeight: coverHeight, alignment: .topLeading)
                .overlay(alignment: .topLeading) {
                    SumiGridBookRepresentable(book: book, anchor: anchor)
                        .frame(width: coverWidth, height: coverHeight)
                        .opacity(isLifted ? 0 : 1)
                }
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
                Divider().padding(.leading, Self.rowInset + coverWidth + Self.coverSpacing)
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
