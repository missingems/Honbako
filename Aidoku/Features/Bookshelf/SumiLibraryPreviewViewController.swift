#if SUMI && DEBUG
import AidokuRunner
import SwiftUI
import UIKit

/// Isolated UI fixtures: generated covers, no additions to the user's library.
final class SumiLibraryPreviewViewController: UIViewController {
    static func makeIfRequested() -> UIViewController? {
        guard ProcessInfo.processInfo.arguments.contains("--sumi-library-check") else { return nil }
        if ProcessInfo.processInfo.arguments.contains("--sumi-library-reset-placement") {
            UserDefaults.standard.removeObject(forKey: "Sumi.libraryPile.placements.v1")
        }
        return UINavigationController(rootViewController: SumiLibraryPreviewViewController())
    }

    private let store = SumiLibraryStore()
    private let visibility = SumiLibraryVisibility()
    private var books: [SumiBook] = []
    private var host: UIHostingController<SumiLibraryPreviewContent>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationController?.setNavigationBarHidden(true, animated: false)
        books = Self.makeBooks()
        let host = UIHostingController(rootView: content)
        self.host = host
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }

    private var content: SumiLibraryPreviewContent {
        SumiLibraryPreviewContent(books: books, visibility: visibility) { [weak self] book, source in
            guard let self else { source?.finish(); return }
            SumiBookPresentation.present(book, store: store, from: self, visibility: visibility, source: source)
        }
    }

    private static func makeBooks() -> [SumiBook] {
        let names = ["One-Punch Man", "Frieren", "Witch Hat Atelier", "Vagabond", "Dandadan", "Blue Period", "Yotsuba!", "The Climber"]
        let colors: [UIColor] = [.systemRed, .systemTeal, .systemOrange, .systemIndigo, .systemPink, .systemBlue, .systemGreen, .brown]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SumiLibraryValidation", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return names.enumerated().map { index, name in
            let image = UIGraphicsImageRenderer(size: CGSize(width: 360, height: 530), format: format).image { context in
                let cg = context.cgContext
                colors[index].setFill()
                cg.fill(CGRect(x: 0, y: 0, width: 360, height: 530))
                UIColor.white.withAlphaComponent(0.14).setFill()
                cg.fillEllipse(in: CGRect(x: 50, y: 80, width: 380, height: 380))
                UIColor.black.withAlphaComponent(0.12).setFill()
                cg.fill(CGRect(x: 0, y: 0, width: 14, height: 530))
                let title: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 42, weight: .black), .foregroundColor: UIColor.white]
                name.draw(in: CGRect(x: 30, y: 45, width: 300, height: 200), withAttributes: title)
                let number: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 170, weight: .ultraLight), .foregroundColor: UIColor.white.withAlphaComponent(0.8)]
                String(index + 1).draw(at: CGPoint(x: 90, y: 260), withAttributes: number)
            }
            let url = directory.appendingPathComponent("cover-\(index).png")
            try? image.pngData()?.write(to: url)
            var manga = AidokuRunner.Manga(sourceKey: "sumi-preview", key: "book-\(index)", title: name)
            manga.cover = url.absoluteString
            manga.description = "A journey told through ink and paper. This generated book belongs to the isolated layout preview. Open a real title from Search to read its chapters and save your place."
            return SumiBook(manga: manga, chapterLabel: "Chapter 12", pageLabel: "Page 8 of 24", progress: 1.0 / 3,
                            isInLibrary: false, lastRead: Date(timeIntervalSince1970: 1_780_000_000))
        }
    }
}

private struct SumiLibraryPreviewContent: View {
    let books: [SumiBook]
    @ObservedObject var visibility: SumiLibraryVisibility
    let openBook: (SumiBook, SumiBookTransitionSource?) -> Void

    var body: some View {
        SumiScatteredLibraryView(books: books, isObscured: visibility.isObscured, openBook: openBook)
    }
}
#endif
