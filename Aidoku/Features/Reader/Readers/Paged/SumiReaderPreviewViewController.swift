#if SUMI && DEBUG
import AidokuRunner
import UIKit

/// Explicit, in-memory UI validation. It never opens or changes the library.
final class SumiReaderPreviewViewController: UIViewController {
    static func makeIfRequested() -> UIViewController? {
        guard ProcessInfo.processInfo.arguments.contains("--sumi-curl-check") else { return nil }
        return UINavigationController(rootViewController: SumiReaderPreviewViewController())
    }

    private let temporaryStore = ReaderTemporaryPageStore()
    private let holding = SumiPreviewReaderDelegate()
    private var reader: ReaderPagedViewController?
    private var started = false
    private var holdingTurn = false
    private var originalArguments: [String: Any]?

    override func viewDidLoad() {
        super.viewDidLoad()
        let defaults = UserDefaults.standard
        let original = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        originalArguments = original
        var settings = original
        settings.merge([
            "Reader.pagedPageLayout": "auto",
            "Reader.pagesToPreload": 8, "Reader.liveText": false,
            AppSettings.dictionary.enable.key: false
        ]) { _, new in new }
        defaults.setVolatileDomain(settings, forName: UserDefaults.argumentDomain)
        let manga = AidokuRunner.Manga(sourceKey: "sumi-preview", key: "paper", title: "Paper preview")
        let reader = ReaderPagedViewController(source: nil, manga: manga, temporaryPageStore: temporaryStore)
        self.reader = reader
        reader.readingMode = ProcessInfo.processInfo.arguments.contains("--sumi-curl-rtl") ? .rtl : .ltr
        reader.delegate = holding
        holding.onProgress = { [weak self] range in
            self?.title = range.count > 1 ? "Pages \(range.lowerBound)–\(range.upperBound)" : "Page \(range.lowerBound)"
        }
        add(child: reader)
        reader.view.frame = view.bounds
        reader.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Previous", primaryAction: UIAction { [weak self] _ in
            guard let reader = self?.reader else { return }
            reader.move(toPage: max(1, reader.currentPage - (reader.view.bounds.width > reader.view.bounds.height ? 2 : 1)), animated: true)
        })
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Next", primaryAction: UIAction { [weak self] _ in
            guard let reader = self?.reader else { return }
            reader.move(toPage: min(8, reader.currentPage + (reader.view.bounds.width > reader.view.bounds.height ? 2 : 1)), animated: true)
        })
        if let next = navigationItem.rightBarButtonItem {
            let hold = UIBarButtonItem(title: "Hold", primaryAction: UIAction { [weak self] _ in
                guard let self, let pager = self.reader?.children.compactMap({ $0 as? SumiPageCurlViewController }).first else { return }
                if holdingTurn {
                    holdingTurn = false
                    pager.debugSettleTurn(completed: true)
                } else {
                    holdingTurn = pager.debugHoldTurn(progress: 0.35)
                }
            })
            let cancel = UIBarButtonItem(title: "Cancel", primaryAction: UIAction { [weak self] _ in
                self?.holdingTurn = false
                self?.reader?.children.compactMap({ $0 as? SumiPageCurlViewController }).first?.debugSettleTurn(completed: false)
            })
            navigationItem.rightBarButtonItems = [next, hold, cancel]
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !started, let reader else { return }
        started = true
        let chapter = AidokuRunner.Chapter(key: "paper-preview")
        reader.chapter = chapter
        reader.viewModel.pages = (1...8).map { number in
            Page(sourceId: "sumi-preview", chapterId: chapter.id, index: number - 1, image: Self.image(number))
        }
        reader.loadPageControllers(chapter: chapter)
        reader.loadPages(in: 1...8)
        reader.view.layoutIfNeeded()
        reader.move(toPage: 1, animated: false)
    }

    deinit {
        if let originalArguments {
            UserDefaults.standard.setVolatileDomain(originalArguments, forName: UserDefaults.argumentDomain)
        }
        let temporaryStore = temporaryStore
        Task { await temporaryStore.removeAll() }
    }

    private static func image(_ number: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 600, height: 900), format: format).image { context in
            let bounds = CGRect(x: 0, y: 0, width: 600, height: 900)
            UIColor(white: 0.98, alpha: 1).setFill()
            context.cgContext.fill(bounds)
            let colors: [UIColor] = [.systemBlue, .systemOrange, .systemGreen, .systemPurple]
            colors[(number - 1) % colors.count].withAlphaComponent(0.12).setFill()
            context.cgContext.fill(bounds.insetBy(dx: 15, dy: 15))
            for row in 0..<9 {
                for column in 0..<6 where (row + column).isMultiple(of: 2) {
                    UIColor.black.withAlphaComponent(0.07).setFill()
                    context.cgContext.fill(CGRect(x: column * 100, y: row * 100, width: 100, height: 100))
                }
            }
            let text = "\(number)"
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 200, weight: .bold), .foregroundColor: UIColor.black]
            text.draw(at: CGPoint(x: 220, y: 330), withAttributes: attributes)
            let rules = UIBezierPath()
            for y in stride(from: 60, through: 840, by: 60) {
                rules.move(to: CGPoint(x: 20, y: y)); rules.addLine(to: CGPoint(x: 580, y: y))
            }
            UIColor.black.withAlphaComponent(0.25).setStroke()
            rules.lineWidth = 1
            rules.stroke()
        }
    }
}

private final class SumiPreviewReaderDelegate: ReaderHoldingDelegate {
    var barsHidden = true
    var onProgress: ((ClosedRange<Int>) -> Void)?
    func hideBars() { barsHidden = true }
    func getNextChapter() -> AidokuRunner.Chapter? { nil }
    func getPreviousChapter() -> AidokuRunner.Chapter? { nil }
    func setChapter(_ chapter: AidokuRunner.Chapter) {}
    func setCurrentPage(_ page: Int, position: Double?) { onProgress?(page...page) }
    func setCurrentPages(_ pages: ClosedRange<Int>) { onProgress?(pages) }
    func setPages(_ pages: [Page]) {}
    func displayPage(_ page: Int) {}
    func setSliderOffset(_ offset: CGFloat) {}
    func setCompleted() {}
}
#endif
