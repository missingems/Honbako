#if SUMI
import Foundation

enum HonbakoAutomationModels {
    struct Connection: Codable, Sendable {
        let endpoint: URL
        let deviceId: String
        let deviceToken: String
    }
    struct PairRequest: Encodable { let code: String; let name: String }
    struct PairResponse: Decodable { let deviceId: String; let deviceToken: String }
    struct Item: Codable, Hashable, Sendable {
        let sourceId: String
        let mangaId: String
    }
    struct LibraryItem: Codable, Sendable {
        let sourceId: String
        let mangaId: String
        let title: String
        var author: String?
        var lastReadPage: Int?
    }
    struct SourceItem: Codable, Sendable {
        let id: String
        let name: String
        let supportsSearch: Bool
    }
    struct Reading: Codable, Equatable, Sendable {
        let sourceId: String
        let mangaId: String
        let title: String
        let chapterId: String
        let chapterTitle: String
        let chapterNumber: Float?
        let volumeNumber: Float?
        let page: Int
        let totalPages: Int?
        let lastVisiblePage: Int?
        var updatedAt: String
        var active: Bool
    }
    struct State: Codable, Sendable {
        var schemaVersion = 1
        let generatedAt: String
        let library: [LibraryItem]
        let sources: [SourceItem]
        let reading: Reading?
        var libraryTruncated = false
        var sourcesTruncated = false

        private enum CodingKeys: String, CodingKey {
            case schemaVersion, generatedAt, library, sources, reading, libraryTruncated, sourcesTruncated
        }
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(schemaVersion, forKey: .schemaVersion)
            try container.encode(generatedAt, forKey: .generatedAt)
            try container.encode(library, forKey: .library)
            try container.encode(sources, forKey: .sources)
            if let reading { try container.encode(reading, forKey: .reading) }
            else { try container.encodeNil(forKey: .reading) }
            try container.encode(libraryTruncated, forKey: .libraryTruncated)
            try container.encode(sourcesTruncated, forKey: .sourcesTruncated)
        }
    }
    struct Payload: Codable, Equatable, Sendable {
        var query: String?
        var sourceIds: [String]?
        var limit: Int?
        var items: [Item]?
        var idempotencyKey: String?
    }
    struct Job: Codable, Identifiable, Equatable, Sendable {
        let id: String
        let kind: String
        let payload: Payload
        let status: String
        let createdAt: String
    }
    struct Jobs: Decodable { let jobs: [Job] }
    struct Match: Codable, Sendable {
        let sourceId: String
        let mangaId: String
        let title: String
        var author: String?
    }
    struct SearchResult: Codable, Sendable {
        let matches: [Match]
        var errors: [String]?
    }
    struct AddResult: Codable, Sendable {
        let added: [Match]
        let alreadyPresent: [Match]
    }
    struct Approval: Identifiable {
        let job: Job
        let items: [Match]
        var id: String { job.id }
    }
    struct JobUpdate: Codable, Sendable {
        let status: String
        var result: HonbakoAutomationJSON?
        var error: String?
        var approvalGranted: Bool?
    }
    struct ImportReceipt: Codable {
        let requested: [Item]
        let result: AddResult
    }
}
#endif
