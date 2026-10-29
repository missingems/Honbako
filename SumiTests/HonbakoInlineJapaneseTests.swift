@testable import Sumi
import Testing
import UIKit

@MainActor
@Suite struct HonbakoInlineJapaneseTests {
    @Test("The same page reuses OCR while a different bitmap and an evicted page are recognized")
    func cachesOnlyMatchingImageIdentityAndBoundsEntries() async throws {
        let probe = InlineJapaneseRecognitionProbe(held: false)
        let store = HonbakoInlineJapaneseRecognitionStore(capacity: 2, recognizer: { image in
            await probe.recognize(image)
        })
        let first = image(.red)
        let second = image(.red)
        let third = image(.blue)
        let result = try await store.regions(for: first)
        #expect(try await store.regions(for: first) == result)
        #expect(await probe.callCount() == 1)
        _ = try await store.regions(for: second)
        #expect(await probe.callCount() == 2)
        _ = try await store.regions(for: third)
        #expect(await store.diagnostics().cachedEntries == 2)
        _ = try await store.regions(for: first)
        #expect(await probe.callCount() == 4)
        #expect(await store.diagnostics().cachedEntries == 2)
    }

    @Test("Two visible halves share a scan and one cancelling does not cancel the other")
    func coalescesClientsWithoutCancellingTheirSibling() async throws {
        let probe = InlineJapaneseRecognitionProbe(held: true)
        defer { Task { await probe.releaseAll() } }
        let store = HonbakoInlineJapaneseRecognitionStore(recognizer: { image in await probe.recognize(image) })
        let page = image(.red)
        let first = Task { try await store.regions(for: page) }
        try await eventually { await probe.callCount() == 1 }
        let second = Task { try await store.regions(for: page) }
        try await eventually { await store.diagnostics().activeClients == 2 }
        first.cancel()
        try await eventually { await store.diagnostics().activeClients == 1 }
        await probe.releaseAll()
        let result = try await second.value
        #expect(!result.isEmpty)
        switch await first.result {
            case .failure(let error): #expect(error is CancellationError)
            case .success: Issue.record("A cancelled page client received a stale result")
        }
        #expect(await probe.callCount() == 1)
        #expect(try await store.regions(for: page) == result)
        #expect(await probe.callCount() == 1)
    }

    @Test("A cancelled queued page is skipped and real OCR stays serial")
    func skipsCancelledQueuedWork() async throws {
        let probe = InlineJapaneseRecognitionProbe(held: true)
        defer { Task { await probe.releaseAll() } }
        let store = HonbakoInlineJapaneseRecognitionStore(recognizer: { image in await probe.recognize(image) })
        let firstImage = image(.red)
        let cancelledImage = image(.green)
        let finalImage = image(.blue)
        let first = Task { try await store.regions(for: firstImage) }
        try await eventually { await probe.callCount() == 1 }
        let cancelled = Task { try await store.regions(for: cancelledImage) }
        try await eventually { await store.diagnostics().inFlight == 2 }
        cancelled.cancel()
        try await eventually { await store.diagnostics().inFlight == 1 }
        let final = Task { try await store.regions(for: finalImage) }
        try await eventually { await store.diagnostics().inFlight == 2 }
        await probe.releaseAll()
        _ = try await first.value
        _ = try await final.value
        _ = await cancelled.result
        #expect(await probe.startedImages() == [ObjectIdentifier(firstImage), ObjectIdentifier(finalImage)])
        #expect(await probe.maximumActive() == 1)
    }

    @Test("An abandoned in-flight scan cannot populate the cache even if OCR returns late")
    func discardsLateCancelledResults() async throws {
        let probe = InlineJapaneseRecognitionProbe(held: true)
        defer { Task { await probe.releaseAll() } }
        let store = HonbakoInlineJapaneseRecognitionStore(recognizer: { image in await probe.recognize(image) })
        let page = image(.red)
        let abandoned = Task { try await store.regions(for: page) }
        try await eventually { await probe.callCount() == 1 }
        abandoned.cancel()
        try await eventually { await store.diagnostics().inFlight == 0 }
        await probe.releaseAll()
        _ = await abandoned.result
        #expect(await store.diagnostics().cachedEntries == 0)
        _ = try await store.regions(for: page)
        #expect(await probe.callCount() == 2)
        #expect(await store.diagnostics().cachedEntries == 1)
    }

    @Test("Preloaded and detached pages stay hidden, expose no words, and never request OCR")
    func detachedPagesDoNotScanOrStealReaderTouches() async {
        let probe = InlineJapaneseRecognitionProbe(held: false)
        let store = HonbakoInlineJapaneseRecognitionStore(recognizer: { image in await probe.recognize(image) })
        let overlay = HonbakoInlineJapaneseOverlayView(recognitionStore: store)
        overlay.frame = CGRect(x: 0, y: 0, width: 300, height: 500)
        overlay.configure(enabled: true, onSelect: nil)
        overlay.update(image: image(.white))
        overlay.setPageVisible(false)
        overlay.layoutIfNeeded()
        #expect(overlay.isHidden)
        #expect(overlay.accessibilityElementsHidden)
        overlay.setPageVisible(true)
        overlay.layoutIfNeeded()
        await Task.yield()
        #expect(await probe.callCount() == 0)
        #expect(overlay.isHidden)
        #expect(overlay.accessibilityElementsHidden)
        #expect(overlay.hitTest(CGPoint(x: 150, y: 250), with: nil) == nil)
        #expect(!HonbakoInlineJapaneseOverlayView.isInteractiveTarget(UIView()))
        overlay.configure(enabled: false, onSelect: nil)
        overlay.update(image: nil)
        #expect(await store.diagnostics().inFlight == 0)
    }

    private func image(_ color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    private func eventually(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { throw InlineJapaneseTestTimeout() }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

private struct InlineJapaneseTestTimeout: Error {}

/// Intentionally ignores task cancellation while held, like an OCR completion
/// racing with a page leaving the screen. The service must reject that result.
private actor InlineJapaneseRecognitionProbe {
    private var held: Bool
    private var pending: [CheckedContinuation<Void, Never>] = []
    private var started: [ObjectIdentifier] = []
    private var active = 0
    private var maximum = 0

    init(held: Bool) { self.held = held }

    func recognize(_ image: UIImage) async -> [HonbakoJapaneseRegion] {
        started.append(ObjectIdentifier(image))
        active += 1
        maximum = max(maximum, active)
        let identifier = started.count
        if held {
            await withCheckedContinuation { pending.append($0) }
        }
        active -= 1
        return [HonbakoJapaneseRegion(
            id: identifier, text: "今日", reading: "きょう", romaji: "kyou", confidence: 1,
            readingIsEstimated: true, direction: .horizontal,
            boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.2, height: 0.1)
        )]
    }

    func releaseAll() {
        held = false
        let continuations = pending
        pending.removeAll()
        continuations.forEach { $0.resume() }
    }

    func callCount() -> Int { started.count }
    func startedImages() -> [ObjectIdentifier] { started }
    func maximumActive() -> Int { maximum }
}
