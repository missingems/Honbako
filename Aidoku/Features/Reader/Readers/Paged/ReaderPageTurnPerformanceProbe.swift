#if DEBUG
import AidokuRunner
import UIKit

/// Isolated, opt-in native curl workload for Instruments. It never opens a
/// source, imports a file, or reports progress to the user's library.
final class ReaderPageTurnPerformanceProbe: UIViewController {
    static let argument = "--aidoku-book-performance-check"

    static func makeIfRequested() -> UIViewController? {
        guard ProcessInfo.processInfo.arguments.contains(argument) else { return nil }
        return ReaderPageTurnPerformanceProbe()
    }

    private struct Turn: Encodable {
        let number: Int
        let fromPage: Int
        let toPage: Int
        let requestedAtUptime: TimeInterval
        var nativeCompletionAtUptime: TimeInterval?
    }

    private struct Report: Encodable {
        let processID = ProcessInfo.processInfo.processIdentifier
        var generatedAt = Date()
        var state = "preparing"
        var maximumFramesPerSecond: Int?
        var presentation = "not-yet-attached"
        var turns: [Turn] = []
        var summary = "DEBUG synthetic in-memory book; timings mark native completions, not rendered FPS."
    }

    private let temporaryStore = ReaderTemporaryPageStore()
    private let holdingDelegate = PerformanceReaderDelegate()
    private var reader: ReaderPagedViewController?
    private var originalArgumentDomain: [String: Any]?
    private var report = Report()
    private var runTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var turnContinuation: CheckedContinuation<Bool, Never>?
    private var pendingTurn: Int?
    private var didStart = false

    override func viewDidLoad() {
        super.viewDidLoad()
        guard ProcessInfo.processInfo.arguments.contains(Self.argument) else { return }
        view.backgroundColor = .systemBackground
        let manga = AidokuRunner.Manga(sourceKey: "native-book-performance", key: "synthetic", title: "Native Book Performance")
        let defaults = UserDefaults.standard
        let original = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        originalArgumentDomain = original
        var overrides = original
        let settings: [String: Any] = [
            "Reader.pagedPageLayout": "double", AppSettings.reader.pageSizing.key: "fit",
            "Reader.pagesToPreload": 8, "Reader.splitWideImages": false,
            "Reader.pagedPageOffset": false, "Reader.pagedPageOffset.\(manga.identifier)": false,
            "Reader.cropBorders": false, "Reader.downsampleImages": false, "Reader.upscaleImages": false,
            "Reader.liveText": false, AppSettings.dictionary.enable.key: false
        ]
        overrides.merge(settings) { _, new in new }
        defaults.setVolatileDomain(overrides, forName: UserDefaults.argumentDomain)
        // This explicitly requested probe measures native curl even when the
        // normal reader appropriately uses Reduce Motion's scroll fallback.
        let reader = ReaderPagedViewController(source: nil, manga: manga, temporaryPageStore: temporaryStore,
                                               reduceMotionEnabled: { false })
        self.reader = reader
        reader.delegate = holdingDelegate
        reader.readingMode = .ltr
        add(child: reader)
        reader.view.frame = view.bounds
        reader.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        holdingDelegate.onProgress = { [weak self] range in self?.receivedProgress(range) }
        writeReport()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStart, let reader else { return }
        didStart = true
        let chapter = AidokuRunner.Chapter(key: "synthetic-native-curl")
        reader.chapter = chapter
        reader.viewModel.pages = (1...8).map { number in
            Page(sourceId: "native-book-performance", chapterId: chapter.id, index: number - 1, image: Self.pageImage(number))
        }
        reader.loadPageControllers(chapter: chapter)
        reader.loadPages(in: 1...8)
        reader.view.frame = view.bounds
        reader.view.layoutIfNeeded()
        reader.move(toPage: 1, animated: false)
        runTask = Task { [weak self] in
            guard let self else { return }
            do {
                // Let images and layout settle before attaching Instruments.
                try await Task.sleep(nanoseconds: 300_000_000)
                reader.view.layoutIfNeeded()
                guard let pager = reader.children.compactMap({ $0 as? UIPageViewController }).first,
                      pager.transitionStyle == .pageCurl, pager.spineLocation == .mid,
                      pager.isDoubleSided, pager.viewControllers?.count == 2 else {
                    report.state = "requires-landscape-native-curl"
                    report.summary = "Open the Duo to a landscape viewport. No performance turns ran."
                    writeReport()
                    return
                }
                report.maximumFramesPerSecond = view.window?.windowScene?.screen.maximumFramesPerSecond
                report.presentation = "UIPageViewController.pageCurl.mid.doubleSided"
                report.state = "ready"
                report.summary = "Eight generated 900x1350 pages; Fit; preloaded; OCR/image processing off; DEBUG Reduce Motion override. Attach within 12 seconds."
                writeReport()
                try await Task.sleep(nanoseconds: 12_000_000_000)
                report.state = "running"
                writeReport()
                for target in Array(repeating: [3, 5, 7, 5, 3, 1], count: 3).flatMap({ $0 }) {
                    try Task.checkCancellation()
                    let start = ProcessInfo.processInfo.systemUptime
                    guard await animateTurn(to: target) else {
                        if !Task.isCancelled { report.state = "native-completion-timeout"; writeReport() }
                        return
                    }
                    // Workload pacing, not an FPS counter. Native UIKit owns
                    // every intermediate animation frame and its actual rate.
                    let pause = max(0, 1 - (ProcessInfo.processInfo.systemUptime - start))
                    if pause > 0 { try await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000)) }
                }
                report.state = "completed"
                report.summary = "18 native animated turns completed. Use Instruments frame lifetimes/vsync/hitches to determine actual rendered cadence; completion timings are not FPS."
                writeReport()
                await temporaryStore.removeAll()
            } catch {
                if report.state != "cancelled" { report.state = "cancelled"; writeReport() }
            }
        }
    }

    private func animateTurn(to target: Int) async -> Bool {
        guard let reader, !Task.isCancelled else { return false }
        let index = report.turns.count
        report.turns.append(Turn(number: index + 1, fromPage: reader.currentPage, toPage: target,
                                 requestedAtUptime: ProcessInfo.processInfo.systemUptime))
        pendingTurn = index
        return await withCheckedContinuation { continuation in
            turnContinuation = continuation
            timeoutTask = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { return }
                self?.finishTurn(completed: false)
            }
            reader.move(toPage: target, animated: true)
        }
    }

    private func receivedProgress(_ range: ClosedRange<Int>) {
        guard let pendingTurn, report.turns.indices.contains(pendingTurn),
              report.turns[pendingTurn].toPage == range.lowerBound else { return }
        report.turns[pendingTurn].nativeCompletionAtUptime = ProcessInfo.processInfo.systemUptime
        finishTurn(completed: true)
    }

    private func finishTurn(completed: Bool) {
        guard let continuation = turnContinuation else { return }
        turnContinuation = nil
        pendingTurn = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation.resume(returning: completed)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        runTask?.cancel()
        runTask = nil
        finishTurn(completed: false)
        if report.state != "completed" { report.state = "cancelled"; writeReport() }
        if let originalArgumentDomain {
            UserDefaults.standard.setVolatileDomain(originalArgumentDomain, forName: UserDefaults.argumentDomain)
            self.originalArgumentDomain = nil
        }
        let store = temporaryStore
        Task { await store.removeAll() }
    }

    private func writeReport() {
        guard ProcessInfo.processInfo.arguments.contains(Self.argument) else { return }
        report.generatedAt = Date()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(report),
              let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        try? data.write(to: caches.appendingPathComponent("AidokuBookPerformance.json"), options: .atomic)
    }

    private static func pageImage(_ number: Int) -> UIImage {
        let size = CGSize(width: 900, height: 1350)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let bounds = CGRect(origin: .zero, size: size)
            UIColor(hue: CGFloat(number - 1) / 8, saturation: 0.24, brightness: 1, alpha: 1).setFill()
            context.fill(bounds)
            UIColor.black.setStroke()
            context.cgContext.setLineWidth(7)
            context.cgContext.stroke(bounds.insetBy(dx: 20, dy: 20))
            let title = "PAGE \(String(format: "%02d", number))"
            title.draw(in: CGRect(x: 40, y: 70, width: 820, height: 220), withAttributes: [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 150, weight: .bold), .foregroundColor: UIColor.black
            ])
            for row in 0..<3 {
                for column in 0..<2 {
                    let panel = CGRect(x: CGFloat(45 + column * 415), y: CGFloat(330 + row * 315), width: 380, height: 275)
                    UIColor.white.setFill()
                    context.fill(panel)
                    UIColor.black.setStroke()
                    context.cgContext.stroke(panel)
                    for line in 0..<7 {
                        let path = UIBezierPath()
                        path.move(to: CGPoint(x: panel.minX + 18, y: panel.minY + 25 + CGFloat(line) * 31))
                        path.addCurve(to: CGPoint(x: panel.maxX - 18, y: panel.minY + 35 + CGFloat(line) * 29),
                                      controlPoint1: CGPoint(x: panel.midX - 90, y: panel.maxY - 20),
                                      controlPoint2: CGPoint(x: panel.midX + 70, y: panel.minY + 15))
                        path.lineWidth = 3
                        path.stroke()
                    }
                }
            }
        }
    }
}

private final class PerformanceReaderDelegate: ReaderHoldingDelegate {
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
