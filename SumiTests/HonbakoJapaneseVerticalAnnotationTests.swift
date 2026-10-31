@testable import Sumi
import CoreGraphics
import Testing
import UIKit

@MainActor
@Suite struct HonbakoJapaneseVerticalAnnotationTests {
    @Test("A clearly vertical page column overrides an incorrect horizontal Vision direction")
    func verticalPageGeometryWins() {
        let column = CGRect(x: 0.7, y: 0.1, width: 0.06, height: 0.4)
        #expect(HonbakoJapaneseGeometry.resolvedDirection(.horizontal, for: column,
            imageSize: CGSize(width: 1200, height: 1800), characterCount: 8) == .vertical)
        #expect(HonbakoJapaneseGeometry.resolvedDirection(.unknown, for: column,
            imageSize: CGSize(width: 1200, height: 1800), characterCount: 8) == .vertical)
        let single = CGRect(x: 0.1, y: 0.1, width: 0.05, height: 0.05)
        #expect(HonbakoJapaneseGeometry.resolvedDirection(.unknown, for: single,
            imageSize: CGSize(width: 1200, height: 1800), characterCount: 1) == .unknown)
        #expect(HonbakoJapaneseGeometry.resolvedDirection(.vertical, for: single,
            imageSize: CGSize(width: 1200, height: 1800), characterCount: 1) == .vertical)
    }

    @Test("Direction inference uses image pixels after orientation, independently of the viewport")
    func orientedPixelsRemainTheSourceOfTruth() {
        let box = CGRect(x: 0.2, y: 0.2, width: 0.2, height: 0.1)
        #expect(HonbakoJapaneseGeometry.resolvedDirection(.unknown, for: box,
            imageSize: CGSize(width: 600, height: 2400), characterCount: 4) == .vertical)
        #expect(HonbakoJapaneseGeometry.resolvedDirection(.unknown, for: box,
            imageSize: CGSize(width: 2400, height: 600), characterCount: 4) == .horizontal)
    }

    @Test("Vertical words prefer upright readings on the right while horizontal words keep the upper row")
    func conventionalSidePreference() throws {
        let page = CGRect(x: 0, y: 0, width: 600, height: 800)
        let column = CGRect(x: 300, y: 100, width: 30, height: 250)
        let word = CGRect(x: 304, y: 170, width: 22, height: 70)
        let size = CGSize(width: 40, height: 24)
        let frame = try #require(HonbakoJapaneseOverlayLayout.wordChipFrame(
            for: word, in: page, size: size, direction: .vertical, containingTextBox: column))
        #expect(frame.minX > column.maxX)
        #expect(frame.midY == word.midY)
        #expect(HonbakoJapaneseOverlaySide.preferred(for: .vertical) == [.after, .before])
        #expect(HonbakoJapaneseOverlaySide.preferred(for: .horizontal) == [.before, .after])
    }

    @Test("Right-to-left columns retain their own word alignment without crossing neighboring Japanese")
    func adjacentColumnsDoNotOverlap() throws {
        let page = CGRect(x: 0, y: 0, width: 600, height: 800)
        let right = CGRect(x: 350, y: 200, width: 24, height: 60)
        let left = CGRect(x: 260, y: 260, width: 24, height: 70)
        let rightChip = try #require(HonbakoJapaneseOverlayLayout.wordChipFrame(
            for: right, in: page, size: CGSize(width: 44, height: 24), direction: .vertical,
            avoiding: [right, left]))
        let leftChip = try #require(HonbakoJapaneseOverlayLayout.wordChipFrame(
            for: left, in: page, size: CGSize(width: 44, height: 24), direction: .vertical,
            avoiding: [right, left, rightChip]))
        #expect(rightChip.minX > leftChip.minX)
        #expect(rightChip.midY == right.midY && leftChip.midY == left.midY)
        #expect(!rightChip.intersects(leftChip) && !leftChip.intersects(right))
    }

    @Test("A page edge or neighboring column uses the clear left side without rotating or covering text")
    func verticalFallbackStaysInsidePage() throws {
        let page = CGRect(x: 0, y: 0, width: 400, height: 600)
        let column = CGRect(x: 370, y: 20, width: 24, height: 70)
        let frame = try #require(HonbakoJapaneseOverlayLayout.wordChipFrame(
            for: column, in: page, size: CGSize(width: 40, height: 24), direction: .vertical,
            avoiding: [column]))
        #expect(frame.maxX < column.minX)
        #expect(page.contains(frame))
        #expect(frame.width == 40 && frame.height == 24)
        #expect(!frame.intersects(column))
    }

    @Test("Long vertical readings wrap upright in a compact column instead of becoming a wide ribbon")
    func compactUprightWordChips() {
        let font = UIFont.systemFont(ofSize: 10)
        let box = CGRect(x: 100, y: 100, width: 24, height: 65)
        let vertical = HonbakoJapaneseAnnotationStyle.labelSize(for: "arigatougozaimasu", font: font,
            direction: .vertical, wordBox: box)
        let horizontal = HonbakoJapaneseAnnotationStyle.labelSize(for: "arigatougozaimasu", font: font,
            direction: .horizontal, wordBox: box)
        #expect(vertical.width <= font.pointSize * 5 + 2)
        #expect(vertical.width < horizontal.width)
        #expect(vertical.height > horizontal.height)
        let label = UILabel()
        label.font = font
        label.text = "arigatougozaimasu"
        label.numberOfLines = 0
        label.lineBreakMode = .byCharWrapping
        let measured = label.sizeThatFits(CGSize(width: vertical.width - 2, height: .greatestFiniteMagnitude))
        #expect(measured.height <= vertical.height - 2)
        let short = HonbakoJapaneseAnnotationStyle.labelSize(for: "kyou", font: font,
            direction: .vertical, wordBox: box)
        #expect(short.height == ceil(font.lineHeight) + 2)
    }

    @Test("Accurate character rectangles can recover a vertical word without dividing the phrase")
    func realCharacterUnion() throws {
        let parent = CGRect(x: 0.7, y: 0.1, width: 0.08, height: 0.5)
        let boxes = [CGRect(x: 0.71, y: 0.12, width: 0.05, height: 0.06),
                     CGRect(x: 0.71, y: 0.20, width: 0.05, height: 0.06)]
        let union = try #require(HonbakoJapaneseWordGeometry.characterUnion(boxes, in: parent))
        #expect(abs(union.minY - 0.12) < 0.000001)
        #expect(abs(union.maxY - 0.26) < 0.000001)
        #expect(parent.contains(union))
        #expect(HonbakoJapaneseWordGeometry.characterUnion([parent, parent], in: parent) == nil)
        #expect(HonbakoJapaneseWordGeometry.characterUnion([boxes[0], boxes[0]], in: parent) == nil)
        #expect(HonbakoJapaneseWordGeometry.characterUnion([CGRect(x: 0.9, y: 0.2, width: 0.05, height: 0.06)], in: parent) == nil)
        #expect(HonbakoJapaneseWordGeometry.characterUnion([], in: parent) == nil)
    }
}
