#if SUMI
import SwiftUI

struct SumiSpotlightResultRow: View {
    private static let rowInset: CGFloat = 8
    private static let coverSpacing: CGFloat = 14

    let book: SumiBook
    let isLifted: Bool
    let isInLibrary: Bool
    let editions: [SumiBook]
    let sourceName: (String) -> String
    let openBook: (SumiBook, SumiBookTransitionSource?) -> Void
    let addBook: (SumiBook, SumiBookTransitionSource?) async -> Void
    var showsDivider = false
    @State private var anchor = SumiBookSourceAnchor()
    @State private var adding = false
    @State private var presentedLanguages: SumiSearchLanguageInfo?
    @ScaledMetric(relativeTo: .body) private var coverScale: CGFloat = 1
    @ScaledMetric(relativeTo: .body) private var rowContentHeight: CGFloat = 124
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var coverWidth: CGFloat { 68 * min(coverScale, 1.5) }
    private var coverHeight: CGFloat { 100 * min(coverScale, 1.5) }
    private var titleInset: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? Self.rowInset : Self.rowInset + coverWidth + Self.coverSpacing
    }

    private var presentation: SumiSearchResultPresentation {
        SumiSearchResultPresentation(book: book, isInLibrary: isInLibrary)
    }
    private var author: String? {
        book.author
    }
    private var languages: SumiSearchLanguageInfo? {
        book.searchLanguages ?? SumiSearchLanguageInfo(chapterLanguages: (book.manga.chapters ?? []).compactMap(\.language),
                                                       sourceLanguages: [])
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
                        .clipShape(ConcentricRectangle(corners: .concentric(minimum: .fixed(8))))
                        .opacity(isLifted ? 0 : 1)
                    VStack(alignment: .leading, spacing: 4) {
                        if let status = presentation.publicationBadge {
                            SumiPublicationStatusBadge(title: status)
                        }
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
                    .accessibilityHint(String(localized: "Open manga"))
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
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private func performAction() {
        if presentation.action == .get { getBook() }
        else { selectBook() }
    }

    private func getBook() {
        guard !adding, !isInLibrary else { return }
        adding = true
        let source = anchor.view.flatMap { SumiBookTransitionSource.capture($0, replacementView: { anchor.view }) }
        Task { await addBook(book, source); adding = false }
    }

    private func selectBook() {
        guard !adding else { return }
        let source = anchor.view.flatMap { SumiBookTransitionSource.capture($0, replacementView: { anchor.view }) }
        openBook(book, source)
    }
}
#endif
