@testable import Sumi
import CoreGraphics
import Testing

@Suite struct HonbakoJapaneseOverlayTests {
    @Test("Romaji sits above Japanese without covering its characters")
    func leavesTextVisible() throws {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 180)
        let text = CGRect(x: 150, y: 60, width: 40, height: 80)
        let chip = try #require(HonbakoJapaneseOverlayLayout.chipFrame(
            for: text, in: bounds, size: CGSize(width: 110, height: 28)))
        #expect(bounds.contains(chip))
        #expect(chip.maxY < text.minY)
        #expect(!chip.intersects(text))
    }

    @Test("Top-edge text uses clear space below and avoids neighboring Japanese")
    func choosesFreeSpace() throws {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 180)
        let topText = CGRect(x: 4, y: 0, width: 100, height: 30)
        let below = try #require(HonbakoJapaneseOverlayLayout.chipFrame(
            for: topText, in: bounds, size: CGSize(width: 120, height: 28)))
        #expect(below.minY > topText.maxY)
        #expect(bounds.contains(below))
        let text = CGRect(x: 20, y: 70, width: 50, height: 30)
        let otherText = CGRect(x: 0, y: 0, width: 200, height: 65)
        let avoiding = try #require(HonbakoJapaneseOverlayLayout.chipFrame(
            for: text, in: bounds, size: CGSize(width: 100, height: 28), avoiding: [otherText]))
        #expect(avoiding.minY > text.maxY)
        #expect(!avoiding.intersects(otherText))
    }

    @Test("Crowded or invalid pages do not draw a chip over Japanese")
    func rejectsBlockedSpace() {
        let page = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(HonbakoJapaneseOverlayLayout.chipFrame(for: page, in: page, size: CGSize(width: 80, height: 28)) == nil)
        #expect(HonbakoJapaneseOverlayLayout.chipFrame(
            for: CGRect(x: 10, y: 40, width: 20, height: 20), in: page,
            size: CGSize(width: CGFloat.nan, height: 28)) == nil)
        #expect(HonbakoJapaneseOverlayLayout.chipFrame(for: .zero, in: page, size: CGSize(width: 20, height: 28)) == nil)
    }
    @Test("Individual word labels align above horizontal text and beside vertical text")
    func individualWordPlacements() throws {
        let page = CGRect(x: 0, y: 0, width: 400, height: 600)
        let horizontal = CGRect(x: 100, y: 120, width: 70, height: 24)
        let above = try #require(HonbakoJapaneseOverlayLayout.wordChipFrame(
            for: horizontal, in: page, size: CGSize(width: 50, height: 28), direction: .horizontal))
        #expect(above.maxY < horizontal.minY)
        #expect(page.contains(above))
        let vertical = CGRect(x: 300, y: 200, width: 28, height: 110)
        let beside = try #require(HonbakoJapaneseOverlayLayout.wordChipFrame(
            for: vertical, in: page, size: CGSize(width: 90, height: 28), direction: .vertical))
        #expect(beside.maxX < vertical.minX || beside.minX > vertical.maxX)
        #expect(!beside.intersects(vertical))
        #expect(page.contains(beside))
    }

    @Test("Unavailable exact anchors and labels too wide for the page do not create misleading word labels")
    func rejectsAmbiguousWords() {
        let line = CGRect(x: 20, y: 50, width: 200, height: 30)
        #expect(HonbakoJapaneseOverlayLayout.distinctWordFrames([0: line, 3: line]).isEmpty)
        let separate = [0: CGRect(x: 20, y: 50, width: 40, height: 30), 3: CGRect(x: 65, y: 50, width: 20, height: 30)]
        #expect(HonbakoJapaneseOverlayLayout.distinctWordFrames(separate).count == 2)
        #expect(HonbakoJapaneseOverlayLayout.wordChipFrame(
            for: line, in: CGRect(x: 0, y: 0, width: 250, height: 200),
            size: CGSize(width: 300, height: 28), direction: .horizontal) == nil)
    }

    @Test("Word labels clear the full text line while retaining the actual word’s alignment")
    func lineClearancePreservesWordAlignment() throws {
        let page = CGRect(x: 0, y: 0, width: 400, height: 600)
        let line = CGRect(x: 80, y: 120, width: 250, height: 32)
        let word = CGRect(x: 100, y: 126, width: 70, height: 18)
        let horizontal = try #require(HonbakoJapaneseOverlayLayout.wordChipFrame(
            for: word, in: page, size: CGSize(width: 50, height: 28), direction: .horizontal,
            containingTextBox: line, avoiding: [line.insetBy(dx: -2, dy: -2)]))
        #expect(horizontal.maxY < line.minY - 2)
        #expect(abs(horizontal.midX - word.midX) < 0.000001)
        let column = CGRect(x: 290, y: 200, width: 45, height: 180)
        let verticalWord = CGRect(x: 297, y: 220, width: 25, height: 60)
        let vertical = try #require(HonbakoJapaneseOverlayLayout.wordChipFrame(
            for: verticalWord, in: page, size: CGSize(width: 90, height: 28), direction: .vertical,
            containingTextBox: column, avoiding: [column.insetBy(dx: -2, dy: -2)]))
        #expect(vertical.maxX < column.minX - 2)
        #expect(abs(vertical.midY - verticalWord.midY) < 0.000001)
    }

    @Test("A fixed ruby row stays on its chosen side instead of scattering labels")
    func fixedRubySide() throws {
        let page = CGRect(x: 0, y: 0, width: 200, height: 250)
        let text = CGRect(x: 40, y: 80, width: 80, height: 22)
        let size = CGSize(width: 50, height: 28)
        let above = try #require(HonbakoJapaneseOverlayLayout.wordChipFrame(
            for: text, in: page, size: size, direction: .horizontal, side: .before))
        let below = try #require(HonbakoJapaneseOverlayLayout.wordChipFrame(
            for: text, in: page, size: size, direction: .horizontal, side: .after))
        #expect(above.maxY < text.minY)
        #expect(below.minY > text.maxY)
        #expect(HonbakoJapaneseOverlayLayout.wordChipFrame(
            for: text, in: page, size: size, direction: .horizontal, side: .before,
            avoiding: [CGRect(x: 0, y: 0, width: 200, height: 80)]) == nil)
    }

}
