@testable import Sumi
import CryptoKit
import Foundation
import Testing
import UIKit

@MainActor
@Suite struct HonbakoPageCoachingPolicyTests {
    private typealias Models = HonbakoPageCoachingModels
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("A drawing must match the exact consented session, page, bitmap, generation and newer revision")
    func acceptsOnlyExactCurrentReference() {
        let reference = pageReference()
        #expect(HonbakoPageCoachingPolicy.accepts(state(for: reference), for: reference, after: 0, now: now))
        for changed in [
            state(for: reference, sessionID: "different-session"),
            state(for: reference, pageID: "different-page"),
            state(for: reference, contentHash: String(repeating: "b", count: 64)),
            state(for: reference, generation: 2),
            state(for: reference, active: false),
            state(for: reference, revision: 0),
            state(for: reference, expiry: now.addingTimeInterval(-1))
        ] {
            #expect(!HonbakoPageCoachingPolicy.accepts(changed, for: reference, after: 0, now: now))
        }
        #expect(!HonbakoPageCoachingPolicy.accepts(state(for: reference, revision: 3),
            for: reference, after: 3, now: now), "A replayed revision cannot repaint a page")
    }

    @Test("Drawing batches are bounded, uniquely identified and atomically reject an invalid mark")
    func validatesWholeDrawingBatch() {
        let reference = pageReference()
        let valid = Models.Annotation(id: "valid", type: .box, rect: .init(x: 0.1, y: 0.2, width: 0.2, height: 0.2))
        let invalid = Models.Annotation(id: "invalid", type: .box, rect: .init(x: 0.9, y: 0.2, width: 0.2, height: 0.2))
        #expect(!HonbakoPageCoachingPolicy.accepts(state(for: reference, marks: [valid, valid]),
            for: reference, after: 0, now: now))
        #expect(!HonbakoPageCoachingPolicy.accepts(state(for: reference, marks: [valid, invalid]),
            for: reference, after: 0, now: now))
        let excessive = (0..<25).map { Models.Annotation(id: "mark-\($0)", type: .box, rect: valid.rect) }
        #expect(!HonbakoPageCoachingPolicy.accepts(state(for: reference, marks: excessive),
            for: reference, after: 0, now: now))
        #expect(HonbakoPageCoachingPolicy.accepts(state(for: reference, marks: []),
            for: reference, after: 0, now: now), "An explicit newer empty batch clears the previous drawing")
    }

    @Test("Marks reject out-of-page geometry, zero arrows, unbounded strokes and hidden payload fields")
    func rejectsUnsafeMarks() {
        let rect = Models.Rect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        let point = Models.Point(x: 0.2, y: 0.3)
        let invalid = [
            Models.Annotation(id: "bad-id!", type: .box, rect: rect),
            Models.Annotation(id: "box", type: .box, rect: rect, text: "extra"),
            Models.Annotation(id: "arrow", type: .arrow, from: point, to: point),
            Models.Annotation(id: "line", type: .stroke, points: [point]),
            Models.Annotation(id: "many", type: .stroke, points: Array(repeating: point, count: 129)),
            Models.Annotation(id: "outside", type: .stroke, points: [point, .init(x: .infinity, y: 0)]),
            Models.Annotation(id: "label", type: .label, rect: rect, text: String(repeating: "a", count: 281)),
            Models.Annotation(id: "control", type: .label, rect: rect, text: "bad\u{0000}note"),
            Models.Annotation(id: "blank", type: .label, rect: rect, text: " \n\t")
        ]
        #expect(invalid.allSatisfy { !HonbakoPageCoachingPolicy.valid($0) })
        #expect(!HonbakoPageCoachingPolicy.valid(Models.Rect(x: 0.8, y: 0, width: 0.20001, height: 0.1)))
        #expect(!HonbakoPageCoachingPolicy.valid(Models.Point(x: .nan, y: 0.2)))
        #expect(HonbakoPageCoachingPolicy.valid(Models.Annotation(id: "note", type: .label,
            rect: rect, text: "A short note\nwith a second line", color: .blue)))
    }

    @Test("Capture metadata must be safe and agree with the displayed image page and spoiler boundary")
    func rejectsUnsafeCaptureMetadata() {
        #expect(HonbakoPageCoachingPolicy.validCapture(capture()))
        for changed in [
            capture(sourceID: "source?token=private"),
            capture(mangaID: "https://name:secret@example.com/book"),
            capture(chapterID: "chapter?accessToken=private"),
            capture(canonicalPage: 0),
            capture(canonicalPage: 11, totalPages: 10),
            capture(canonicalPage: 2, lastVisiblePage: 1),
            capture(canonicalPage: 2, totalPages: 10, lastVisiblePage: 11),
            capture(chapterNumber: .nan),
            capture(type: .nextInfoPage),
            capture(pageSourceID: "different-source")
        ] {
            #expect(!HonbakoPageCoachingPolicy.validCapture(changed))
        }
    }

    @Test("Only a bounded canonical JPEG and its content hash leave the phone")
    func encoderProducesBoundedCanonicalPage() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let bitmap = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 1800), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 1800))
            UIColor.black.setFill()
            context.fill(CGRect(x: 100, y: 200, width: 300, height: 400))
        }
        let encoded = try #require(HonbakoPageCoachingImageEncoder.encode(bitmap))
        let bytes = try #require(Data(base64Encoded: encoded.image.data))
        #expect(bytes.count <= HonbakoPageCoachingPolicy.maximumImageBytes)
        #expect(encoded.image.mimeType == "image/jpeg")
        #expect(max(encoded.image.width, encoded.image.height) <= 1600)
        #expect(UIImage(data: bytes) != nil)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        #expect(encoded.contentHash == hash)
    }

    private func pageReference() -> Models.PageReference {
        let context = Models.PageContext(pageId: "22222222-2222-4222-8222-222222222222", contentHash: String(repeating: "a", count: 64),
            sourceId: "fixture-source", mangaId: "fixture-book", title: "Original fixture", chapterId: "fixture-chapter",
            chapterTitle: "Chapter 1", chapterNumber: 1, page: 1, totalPages: 10, lastVisiblePage: 1,
            capturedAt: HonbakoPageCoachingPolicy.timestamp(now))
        return .init(sessionId: "11111111-1111-4111-8111-111111111111", pageGeneration: 1, page: context)
    }

    private func state(for reference: Models.PageReference, sessionID: String? = nil, pageID: String? = nil,
                       contentHash: String? = nil, generation: Int? = nil, active: Bool = true, revision: Int = 1,
                       expiry: Date? = nil, marks: [Models.Annotation] = []) -> Models.State {
        .init(active: active, sessionId: sessionID ?? reference.sessionId, pageId: pageID ?? reference.pageId,
            contentHash: contentHash ?? reference.contentHash, pageGeneration: generation ?? reference.pageGeneration,
            expiresAt: HonbakoPageCoachingPolicy.timestamp(expiry ?? now.addingTimeInterval(100)),
            annotationRevision: revision, annotations: marks, reason: nil)
    }

    private func capture(sourceID: String = "fixture-source", mangaID: String = "fixture-book",
                         chapterID: String = "fixture-chapter", canonicalPage: Int = 1, totalPages: Int = 10,
                         lastVisiblePage: Int? = 1, chapterNumber: Double = 1, type: Page.PageType = .imagePage,
                         pageSourceID: String? = nil) -> HonbakoPageCoachingCapture {
        let page = Page(type: type, sourceId: pageSourceID ?? sourceID, chapterId: chapterID)
        return .init(page: page, source: nil, sourceId: sourceID, mangaId: mangaID, title: "Original fixture",
            chapterId: chapterID, chapterTitle: "Chapter 1", chapterNumber: chapterNumber,
            canonicalPage: canonicalPage, totalPages: totalPages, lastVisiblePage: lastVisiblePage)
    }
}
