//
//  ReaderTextPageGeometryTests.swift
//  AidokuTests
//

@testable import Aidoku
import AidokuRunner
import Testing
import UIKit

@MainActor
struct ReaderTextPageGeometryTests {
    @Test("An unpaired final text page keeps its spread slot and asymmetric safe area")
    func unpairedFinalPageLayout() throws {
        let size = CGSize(width: 1100, height: 900)
        let safeArea = UIEdgeInsets(top: 24, left: 12, bottom: 34, right: 66)
        let config = PaginationConfig()
        let geometry = ReaderTextPageGeometry(
            size: size,
            safeAreaInsets: safeArea,
            usesDoublePages: true,
            config: config
        )
        let content = NSAttributedString(string: "The final unpaired page.")
        let page = TextPage(id: 2, attributedContent: content, markdownContent: content.string, range: NSRange(location: 0, length: content.length))
        let controller = TextDoublePageViewController(leftPage: page, rightPage: nil, direction: .ltr, geometry: geometry)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(origin: .zero, size: size)
        controller.view.layoutIfNeeded()
        controller.viewDidLayoutSubviews()

        let stack = try #require(controller.view.subviews.compactMap { $0 as? UIStackView }.first)
        let textView = try #require(stack.arrangedSubviews.first as? UITextView)
        let blankView = try #require(stack.arrangedSubviews.last as? UITextView)
        let contentSize = TextPaginator(config: config).contentSize(for: geometry.pageSize)

        #expect(stack.frame.minX == safeArea.left)
        #expect(stack.frame.maxX == size.width - safeArea.right)
        let displayPixel = 1 / max(1, controller.traitCollection.displayScale)
        let renderedContentWidth = textView.bounds.width - textView.textContainerInset.left - textView.textContainerInset.right
        #expect(abs(renderedContentWidth - contentSize.width) <= displayPixel)
        #expect(textView.textContainer.size.width == contentSize.width)
        #expect(blankView.textContainer.size.width == contentSize.width)
        #expect(textView.bounds.height - textView.textContainerInset.top - textView.textContainerInset.bottom == contentSize.height)
        #expect(blankView.text.isEmpty)
    }

    @Test("Double-page reader uses a spread for a chapter with one final page")
    func singlePageChapterUsesSpread() throws {
        let previousLayout = UserDefaults.standard.object(forKey: "Reader.pagedPageLayout")
        UserDefaults.standard.set("double", forKey: "Reader.pagedPageLayout")
        defer { UserDefaults.standard.set(previousLayout, forKey: "Reader.pagedPageLayout") }

        let manga = AidokuRunner.Manga(sourceKey: "test", key: "odd-final-page", title: "Test")
        let reader = ReaderPagedTextViewController(source: nil, manga: manga)
        reader.loadViewIfNeeded()
        reader.view.frame = CGRect(x: 0, y: 0, width: 1100, height: 900)
        reader.viewModel.pages = [Page(sourceId: "test", chapterId: "test", text: "A final unpaired page.")]
        reader.viewDidLayoutSubviews()

        let pageController = try #require(reader.children.first as? UIPageViewController)
        let spread = try #require(pageController.viewControllers?.first as? TextDoublePageViewController)
        #expect(spread.leftPage.id == 0)
        #expect(spread.rightPage == nil)
    }

    @Test("Paginated text and rendered text use the same asymmetric safe area", arguments: [false, true])
    func textAreaMatchesPaginator(usesDoublePages: Bool) {
        let size = CGSize(width: 1100, height: 900)
        let safeArea = UIEdgeInsets(top: 24, left: 12, bottom: 34, right: 66)
        let config = PaginationConfig()
        let geometry = ReaderTextPageGeometry(
            size: size,
            safeAreaInsets: safeArea,
            usesDoublePages: usesDoublePages,
            config: config
        )
        let paginatedSize = TextPaginator(config: config).contentSize(for: geometry.pageSize)
        let textViewWidth = usesDoublePages
            ? (size.width - geometry.spreadOuterInsets.left - geometry.spreadOuterInsets.right
                - ReaderTextPageGeometry.spreadSpacing) / 2
            : size.width
        let renderedSize = CGSize(
            width: textViewWidth - geometry.textInsets.left - geometry.textInsets.right,
            height: size.height - geometry.textInsets.top - geometry.textInsets.bottom
        )

        #expect(renderedSize == paginatedSize)
    }

    @Test("Moving side controls preserves equal spread widths")
    func asymmetricInsetsMoveAcrossSpread() {
        let size = CGSize(width: 1100, height: 900)
        let config = PaginationConfig()
        let left = ReaderTextPageGeometry(
            size: size,
            safeAreaInsets: UIEdgeInsets(top: 24, left: 66, bottom: 34, right: 0),
            usesDoublePages: true,
            config: config
        )
        let right = ReaderTextPageGeometry(
            size: size,
            safeAreaInsets: UIEdgeInsets(top: 24, left: 0, bottom: 34, right: 66),
            usesDoublePages: true,
            config: config
        )

        #expect(left.pageSize == right.pageSize)
        #expect(left.textInsets == right.textInsets)
        #expect(left.spreadOuterInsets.left == right.spreadOuterInsets.right)
        #expect(left != right)
    }
}
