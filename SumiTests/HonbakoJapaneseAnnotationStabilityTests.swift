@testable import Sumi
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct HonbakoJapaneseAnnotationStabilityTests {
    @Test("Image relayout inside a chrome animation keeps existing labels and never slides their geometry")
    func annotationsDoNotInheritChromeAnimation() async throws {
        let fixture = try await makeFixture()
        defer { fixture.close() }
        let overlay = fixture.overlay
        let before = try #require(wordChips(overlay).first)
        let initial = before.frame
        var inheritedDuration: TimeInterval = 0
        let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) {
            inheritedDuration = UIView.inheritedAnimationDuration
            overlay.updateImageFrame(CGRect(x: 34, y: 86, width: 324, height: 460))
        }
        animator.startAnimation()
        defer { animator.stopAnimation(true) }
        try await Task.sleep(for: .milliseconds(30))
        #expect(inheritedDuration > 0.5, "Exercise layout inside a real inherited UIKit animation")
        let after = try #require(wordChips(overlay).first)
        #expect(after === before, "The same word must retain its native label instead of re-entering from a zero frame")
        #expect(after.frame != initial, "The new image geometry must still update genuine word anchors")
        for view in [overlay, after] + after.subviews {
            #expect((view.layer.animationKeys() ?? []).isEmpty,
                    "Annotation geometry must not acquire a separate animation from the chrome")
            if let presented = view.layer.presentation() {
                #expect(abs(presented.position.x - view.layer.position.x) < 0.5)
                #expect(abs(presented.position.y - view.layer.position.y) < 0.5)
            }
        }
        #expect(await fixture.probe.calls == 1, "Relayout must reuse the recognized page")
    }

    @Test("Repeated visible-page and chrome layout passes keep label identity and do not rescan or tint them blue")
    func unchangedPageKeepsItsLabels() async throws {
        let fixture = try await makeFixture()
        defer { fixture.close() }
        let overlay = fixture.overlay
        let before = try #require(wordChips(overlay).first)
        let frame = before.frame
        for _ in 0..<4 {
            overlay.configure(enabled: true, onSelect: nil)
            overlay.setPageVisible(true)
            overlay.updateImageFrame(overlay.frame)
        }
        let after = try #require(wordChips(overlay).first)
        #expect(after === before)
        #expect(after.frame == frame)
        #expect(after.layer.borderWidth == 0, "Reading labels have no accent outline")
        let title = try #require(after.subviews.compactMap { $0 as? UILabel }.first)
        #expect(title.textColor == UIColor.black)
        #expect(after.subviews.allSatisfy { !($0 is UIVisualEffectView) }, "Romaji is plain text on the original artwork")
        #expect(await fixture.probe.calls == 1)
    }

    @Test("Compact annotation text stays opaque and grows without clipping at accessibility sizes")
    func compactLabelsKeepDynamicTypeAndLegibility() async throws {
        let fixture = try await makeFixture()
        defer { fixture.close() }
        let overlay = fixture.overlay
        overlay.traitOverrides.preferredContentSizeCategory = .large
        overlay.updateImageFrame(overlay.frame)
        let chip = try #require(wordChips(overlay).first)
        let title = try #require(chip.subviews.compactMap { $0 as? UILabel }.first)
        let initialFontSize = title.font.pointSize
        let initialHeight = chip.bounds.height
        #expect(initialFontSize < UIFont.preferredFont(forTextStyle: .caption1).pointSize)
        #expect(chip.alpha == 1 && title.alpha == 1, "Plain romaji must remain legible")
        #expect(chip.bounds.width >= title.intrinsicContentSize.width)
        #expect(chip.bounds.height >= title.intrinsicContentSize.height)

        overlay.traitOverrides.preferredContentSizeCategory = .accessibilityExtraLarge
        overlay.updateImageFrame(overlay.frame)
        overlay.layoutIfNeeded()
        let enlarged = try #require(wordChips(overlay).first)
        #expect(enlarged === chip)
        #expect(title.font.pointSize > initialFontSize, "Smaller default labels must still respect the reader's text size")
        #expect(enlarged.bounds.height > initialHeight)
        #expect(enlarged.bounds.width >= title.intrinsicContentSize.width)
        #expect(enlarged.bounds.height >= title.intrinsicContentSize.height)
        #expect(await fixture.probe.calls == 1, "Changing text size must not rescan the artwork")
    }

    @Test("Individual kana labels follow horizontal and vertical glyphs without material or theme tint")
    func plainCharacterLabelsFollowPageAxisAndInk() async throws {
        for direction in [HonbakoJapaneseRegion.Direction.horizontal, .vertical] {
            for ink in [HonbakoJapaneseInk.black, .white] {
                let fixture = try await makeFixture(direction: direction, ink: ink)
                defer { fixture.close() }
                fixture.overlay.traitOverrides.userInterfaceStyle = ink == .black ? .dark : .light
                let chips = wordChips(fixture.overlay).sorted { $0.accessibilityIdentifier! < $1.accessibilityIdentifier! }
                #expect(chips.count == 3)
                let labels = chips.compactMap { $0.subviews.compactMap { $0 as? UILabel }.first }
                #expect(labels.map(\.text) == ["ma", "shi", "ta"])
                #expect(labels.allSatisfy { $0.textColor == (ink == .black ? UIColor.black : UIColor.white) })
                #expect(chips.allSatisfy { $0.subviews.allSatisfy { !($0 is UIVisualEffectView) } })
                for (index, chip) in chips.enumerated() {
                    let anchor = characterBox(index: index, direction: direction)
                    let rect = try #require(HonbakoJapaneseGeometry.rect(for: anchor, in: fixture.overlay.bounds))
                    if direction == .vertical {
                        #expect(chip.frame.minX > rect.maxX)
                        #expect(abs(chip.frame.midY - rect.midY) < 0.1)
                    } else {
                        #expect(chip.frame.maxY < rect.minY)
                        #expect(abs(chip.frame.midX - rect.midX) < 0.1)
                    }
                }
            }
        }
    }

    private func characterBox(index: Int, direction: HonbakoJapaneseRegion.Direction) -> CGRect {
        if direction == .vertical {
            return CGRect(x: 0.5, y: 0.2 + Double(index) * 0.1, width: 0.1, height: 0.08)
        }
        return CGRect(x: 0.2 + Double(index) * 0.1, y: 0.3, width: 0.08, height: 0.1)
    }

    private func makeFixture(direction: HonbakoJapaneseRegion.Direction = .horizontal,
                             ink: HonbakoJapaneseInk = .black) async throws -> AnnotationFixture {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let root = UIViewController()
        window.rootViewController = root
        root.view.backgroundColor = .white
        let word = HonbakoJapaneseWord(id: 0, text: "ました", reading: "ました", romaji: "mashita",
            readingIsEstimated: false, range: NSRange(location: 0, length: 3))
        let box = (0..<3).map { characterBox(index: $0, direction: direction) }.reduce(CGRect.null) { $0.union($1) }
        let characters = HonbakoJapaneseCharacterReadings.units(for: word).enumerated().map { index, character in
            HonbakoJapaneseCharacterRegion(character: character,
                boundingBox: characterBox(index: index, direction: direction), ink: ink)
        }
        let region = HonbakoJapaneseRegion(id: 1, text: word.text, reading: word.reading,
            romaji: word.romaji, confidence: 1, readingIsEstimated: false,
            direction: direction, boundingBox: box, words: [.init(word: word, boundingBox: box)], characters: characters)
        let probe = AnnotationRecognitionProbe(region: region)
        let store = HonbakoInlineJapaneseRecognitionStore(recognizer: { _ in await probe.recognize() })
        let overlay = HonbakoInlineJapaneseOverlayView(recognitionStore: store)
        overlay.frame = CGRect(x: 24, y: 80, width: 300, height: 450)
        root.view.addSubview(overlay)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: overlay.bounds.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(overlay.bounds)
        }
        overlay.configure(enabled: true, onSelect: nil)
        overlay.update(image: image)
        overlay.setPageVisible(true)
        window.makeKeyAndVisible()
        let deadline = ContinuousClock.now + .seconds(3)
        while wordChips(overlay).isEmpty, ContinuousClock.now < deadline {
            window.layoutIfNeeded()
            overlay.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        if wordChips(overlay).isEmpty {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
            Issue.record("The active manga image did not produce its injected Japanese word label")
            throw AnnotationFixtureError()
        }
        return AnnotationFixture(window: window, previousKeyWindow: previousKeyWindow, overlay: overlay, probe: probe)
    }

    private func wordChips(_ overlay: HonbakoInlineJapaneseOverlayView) -> [UIView] {
        overlay.subviews.filter { $0.accessibilityIdentifier?.hasPrefix("Honbako.Reader.Japanese.Word.") == true }
    }
}

@MainActor
private struct AnnotationFixture {
    let window: UIWindow
    let previousKeyWindow: UIWindow?
    let overlay: HonbakoInlineJapaneseOverlayView
    let probe: AnnotationRecognitionProbe

    func close() {
        window.isHidden = true
        window.rootViewController = nil
        previousKeyWindow?.makeKey()
    }
}

private actor AnnotationRecognitionProbe {
    let region: HonbakoJapaneseRegion
    private(set) var calls = 0

    init(region: HonbakoJapaneseRegion) { self.region = region }

    func recognize() -> [HonbakoJapaneseRegion] {
        calls += 1
        return [region]
    }
}

private struct AnnotationFixtureError: Error {}
