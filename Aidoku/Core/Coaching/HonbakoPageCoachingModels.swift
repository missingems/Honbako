#if SUMI
import Foundation

enum HonbakoPageCoachingModels {
    struct Point: Codable, Equatable, Sendable {
        let x: Double
        let y: Double
    }
    struct Rect: Codable, Equatable, Sendable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }
    struct Annotation: Codable, Equatable, Identifiable, Sendable {
        enum Kind: String, Codable, Sendable { case box, arrow, label, stroke }
        enum Color: String, Codable, Sendable { case yellow, blue, green, pink }
        let id: String
        let type: Kind
        var rect: Rect?
        var from: Point?
        var to: Point?
        var text: String?
        var points: [Point]?
        var color: Color?
    }
    struct PageContext: Codable, Equatable, Sendable {
        let pageId: String
        let contentHash: String
        let sourceId: String
        let mangaId: String
        let title: String
        let chapterId: String
        let chapterTitle: String
        var chapterNumber: Double?
        let page: Int
        var totalPages: Int?
        var lastVisiblePage: Int?
        var capturedAt: String
    }
    struct PageReference: Equatable, Sendable {
        let sessionId: String
        let pageGeneration: Int
        let page: PageContext
        var pageId: String { page.pageId }
        var contentHash: String { page.contentHash }
    }
    struct Image: Codable, Sendable {
        let mimeType: String
        let data: String
        let width: Int
        let height: Int
    }
    struct Publish: Codable, Sendable {
        let sessionId: String
        let pageGeneration: Int
        let page: PageContext
        let image: Image
        let expiresAt: String?
        var accessMode: String? = nil
    }
    struct Published: Decodable, Sendable {
        let ok: Bool
        let sessionId: String
        let pageId: String
        let expiresAt: String?
        var accessMode: String? = nil
        let annotationRevision: Int
    }
    struct State: Decodable, Sendable {
        let active: Bool
        let sessionId: String?
        let pageId: String?
        let contentHash: String?
        let pageGeneration: Int?
        let expiresAt: String?
        let annotationRevision: Int
        let annotations: [Annotation]
        let reason: String?
        var accessMode: String? = nil
    }
    struct Pause: Encodable {
        let sessionId: String
        let pageGeneration: Int
        let pageId: String
    }
    struct Session: Encodable {
        let sessionId: String
    }
}
#endif
