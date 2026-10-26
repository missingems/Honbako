@testable import Aidoku
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct ReaderBookReferenceTests {
    @Test("Wide leaves share the original bitmap and upgrade a smaller preload for the full display")
    func fullWidthResolutionAndImageFanout() async throws {
        let settings: [String: Any] = [
            "Reader.downsampleImages": true, "Reader.cropBorders": false,
            "Reader.upscaleImages": false, "Reader.liveText": false,
            AppSettings.dictionary.enable.key: false
        ]
        var saved: [String: Any] = [:]
        for (key, value) in settings {
            saved[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.set(value, forKey: key)
        }
        defer { for key in settings.keys { UserDefaults.standard.set(saved[key], forKey: key) } }
        let store = ReaderTemporaryPageStore()
        do {
            let canonical = ReaderPageViewController(type: .page, delegate: nil, temporaryPageStore: store)
            let pageView = try #require(canonical.pageView)
            let left = ReaderBookWideLeafViewController(canonicalController: canonical, side: .left)
            let right = ReaderBookWideLeafViewController(canonicalController: canonical, side: .right)
            left.loadViewIfNeeded()
            right.loadViewIfNeeded()
            var notifications = 0
            pageView.onReferenceContentChanged = { [weak left, weak right] in
                notifications += 1
                left?.refreshImage()
                right?.refreshImage()
            }
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let original = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1200), format: format).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1200))
                UIColor.black.setFill()
                context.fill(CGRect(x: 1150, y: 100, width: 100, height: 1000))
            }
            let page = Page(sourceId: "book-reference-test", chapterId: UUID().uuidString, image: original)
            pageView.updateReferenceViewport(width: 300, displayScale: 1)
            #expect(await pageView.setPage(page))
            let preload = try #require(pageView.imageView.image)
            #expect(preload.cgImage?.width == 300)
            #expect(left.imageView.image === preload)
            #expect(right.imageView.image === preload)

            pageView.updateReferenceViewport(width: 900, displayScale: 2)
            for _ in 0..<100 {
                if pageView.imageView.image?.cgImage?.width == 1800 { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            let upgraded = try #require(pageView.imageView.image)
            #expect(upgraded.cgImage?.width == 1800)
            #expect(left.imageView.image === upgraded)
            #expect(right.imageView.image === upgraded)
            #expect(notifications >= 2)
            #expect(original.cgImage?.width == 2400)
            #expect(page.image === original)

            // A smaller window retains the usable larger bitmap instead of
            // reloading and temporarily replacing both visible paper leaves.
            pageView.updateReferenceViewport(width: 300, displayScale: 1)
            try await Task.sleep(nanoseconds: 30_000_000)
            #expect(pageView.imageView.image === upgraded)
            canonical.clearPage()
            #expect(left.imageView.image == nil)
            #expect(right.imageView.image == nil)
            await store.removeAll()
        } catch {
            await store.removeAll()
            throw error
        }
    }
}
