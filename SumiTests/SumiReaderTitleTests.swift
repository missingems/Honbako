@testable import Sumi
import Testing
import AidokuRunner
import UIKit

@MainActor
struct SumiReaderTitleTests {
    @Test("Reader uses the native manga navigation title and chapter subtitle")
    func nativeNavigationTitle() {
        let reader = ReaderViewController(source: nil,
            manga: AidokuRunner.Manga(sourceKey: "title-test", key: "one", title: "One Punch Man"),
            chapter: .init(key: "first", title: "The Hero", chapterNumber: 1))
        reader.loadNavbarTitle()
        #expect(reader.navigationItem.title == "One Punch Man")
        #expect(reader.navigationItem.titleView == nil, "UIKit owns the title layout rather than a floating custom view")
        if #available(iOS 26.0, *) { #expect(reader.navigationItem.subtitle == "Chapter 1") }
        reader.chapter = .init(key: "second", title: "The next chapter", chapterNumber: 2.5)
        reader.loadNavbarTitle()
        #expect(reader.navigationItem.title == "One Punch Man")
        if #available(iOS 26.0, *) { #expect(reader.navigationItem.subtitle == "Chapter 2.5") }
    }

    #if HONBAKO_EXTERNAL_SOURCES
    @Test("An automatic readable edition explicitly identifies the actual chapter language in the native subtitle")
    func automaticEditionSubtitle() {
        let reader = ReaderViewController(source: nil,
            manga: AidokuRunner.Manga(sourceKey: "title-test", key: "fallback", title: "Fixture"),
            chapter: .init(key: "az-first", chapterNumber: 1, language: "az"))
        reader.sumiAutomaticOpeningLanguage = "az"
        reader.loadNavbarTitle()
        if #available(iOS 26.0, *) {
            #expect(reader.navigationItem.subtitle == "Chapter 1 · \(SourceLanguage.displayName(for: "az"))")
        }
        reader.sumiAutomaticOpeningLanguage = nil
        reader.loadNavbarTitle()
        if #available(iOS 26.0, *) { #expect(reader.navigationItem.subtitle == "Chapter 1") }
    }
    #endif

    @Test("Sources without chapter numbers retain their named chapter as the native subtitle")
    func namedChapterSubtitle() {
        let reader = ReaderViewController(source: nil,
            manga: AidokuRunner.Manga(sourceKey: "title-test", key: "two", title: "Our Manga"),
            chapter: .init(key: "one", title: "A quiet beginning"))
        reader.loadNavbarTitle()
        #expect(reader.navigationItem.title == "Our Manga")
        if #available(iOS 26.0, *) { #expect(reader.navigationItem.subtitle == "A quiet beginning") }
    }

    @Test("The closed display title respects the physical status rail and camera")
    func closedDisplay() {
        let bounds = CGRect(x: 0, y: 0, width: 466, height: 678)
        let camera = CGRect(x: 402, y: 0, width: 64, height: 100)
        let frame = SumiReaderTitleLayout.frame(in: bounds,
            safeAreaInsets: UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 84), avoiding: [camera],
            size: CGSize(width: 300, height: 36), side: nil)
        #expect(frame.maxX <= bounds.maxX - 84)
        #expect(frame.minY >= 8)
        #expect(!frame.intersects(camera))
    }

    @Test("Titles stay within one leaf when a fold divides the inner display")
    func foldedDisplay() {
        let bounds = CGRect(x: 0, y: 0, width: 951, height: 669)
        let fold = CGRect(x: 460, y: 0, width: 31, height: 669)
        for side in [UIRectEdge.left, .right] {
            let frame = SumiReaderTitleLayout.frame(in: bounds, safeAreaInsets: .zero, avoiding: [fold],
                size: CGSize(width: 480, height: 36), side: side)
            #expect(!frame.intersects(fold))
            #expect(bounds.contains(frame))
            if side == .left { #expect(frame.maxX <= fold.minX) }
            else { #expect(frame.minX >= fold.maxX) }
        }
    }

    @Test("Portrait titles remain centered below the actual top safe area")
    func portraitDisplay() {
        let bounds = CGRect(x: 0, y: 0, width: 402, height: 874)
        let frame = SumiReaderTitleLayout.frame(in: bounds,
            safeAreaInsets: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0), avoiding: [],
            size: CGSize(width: 180, height: 36), side: nil)
        #expect(frame.midX == bounds.midX)
        #expect(frame.minY == 67)
        #expect(frame.width == 180 && frame.height == 36)
    }
}
