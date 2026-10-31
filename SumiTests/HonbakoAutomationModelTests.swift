@testable import Sumi
import Foundation
import Testing

@Suite struct HonbakoAutomationModelTests {
    private typealias Models = HonbakoAutomationModels
    private let timestamp = "2026-10-29T12:00:00Z"

    @Test("Bridge endpoints keep tokens out of URLs and reject unsupported transports")
    func endpointAuthenticationAndTransportBoundary() {
        for endpoint in [
            "https://user:secret@example.com/bridge", "https://secret@example.com",
            "https://example.com/bridge?token=secret", "https://example.com/bridge?",
            "https://example.com/bridge#secret", "https://example.com/bridge#",
            "file:///private/bridge", "ftp://localhost/bridge", "ws://localhost/bridge",
            "mailto:agent@example.com", "data:text/plain,secret", "not a URL", "",
            "https://example.com:0", "https://example.com:65536"
        ] {
            #expect(HonbakoAutomationPolicy.endpoint(endpoint) == nil, "Unexpected accepted endpoint: \(endpoint)")
        }
        #expect(HonbakoAutomationPolicy.endpoint("https://bridge.example.com/api") != nil)
        #expect(HonbakoAutomationPolicy.endpoint("  HTTPS://EXAMPLE.COM/api/  ")?.absoluteString == "https://example.com/api")
    }

    @Test("Plain HTTP is confined to canonical local or private hosts, including IPv6")
    func httpIsLocalOnly() {
        for host in ["localhost", "reader.local", "127.0.0.1", "127.3.4.5", "10.1.2.3",
                     "172.16.0.1", "172.31.255.254", "192.168.1.10", "169.254.1.2",
                     "[::1]", "[fd12:3456::1]", "[fe80::1]"] {
            #expect(HonbakoAutomationPolicy.endpoint("http://\(host):8765") != nil, "Local endpoint rejected: \(host)")
        }
        for host in ["example.com", "8.8.8.8", "172.15.0.1", "172.32.0.1", "192.169.1.1",
                     "localhost.example.com", "192.168.1.1.example.com", "reader.local.example.com",
                     "256.0.0.1", "10.0.0.999", "010.0.0.1", "0172.16.0.1",
                     "2130706433", "0x7f000001", "[2001:4860:4860::8888]", "[::ffff:8.8.8.8]"] {
            #expect(HonbakoAutomationPolicy.endpoint("http://\(host):8765") == nil, "Remote or ambiguous HTTP host accepted: \(host)")
        }
    }

    @Test("Bridge path prefixes and route identifiers cannot traverse parent routes")
    func traversalCannotEscapeBridgeRoutes() {
        for path in ["/api/../devices", "/./devices", "/api/%2e%2e/devices", "/api/%2E/devices", "/api/%5c/devices"] {
            #expect(HonbakoAutomationPolicy.endpoint("https://example.com\(path)") == nil)
        }
        #expect(HonbakoAutomationPolicy.endpoint("https://example.com/honbako/v1") != nil)
        #expect(HonbakoAutomationPolicy.validIdentifier("device_123-abc"))
        for identifier in ["", ".", "..", "../device", "device/other", "device%2Fother", "device?admin=true", "device\n", String(repeating: "x", count: 129)] {
            #expect(!HonbakoAutomationPolicy.validIdentifier(identifier))
        }
    }

    @Test("Reading snapshots describe only valid one-based canonical pages and visible spread bounds")
    func readingBoundaryUsesCanonicalPages() {
        #expect(reading(page: 3, total: 20, visible: 4)?.lastVisiblePage == 4)
        #expect(reading(page: 20, total: 20, visible: 20)?.page == 20)
        #expect(reading(page: 1, total: nil, visible: 1) != nil)
        #expect(reading(page: 3, total: nil, visible: 4) != nil)
        for (page, total, visible) in [(0, 20, 1), (-1, 20, 1), (5, 4, 5),
                                        (3, 20, 2), (3, 4, 5), (3, 0, 3), (3, -2, 3), (3, 20, 0)] {
            #expect(reading(page: page, total: total, visible: visible) == nil,
                    "An invalid page range must not become agent context")
        }
        for invalid in [Float.nan, .infinity, -.infinity] {
            #expect(reading(chapterNumber: invalid) == nil)
            #expect(reading(volumeNumber: invalid) == nil)
        }
        #expect(reading(chapterNumber: 2.5, volumeNumber: 1) != nil)
    }

    @Test("Authenticated provider URLs cannot leak through reading or catalog item identifiers")
    func sourceCredentialsAreNotExportableIdentifiers() {
        for identifier in ["https://user:secret@example.com/book", "https://example.com/book?token=secret",
                           "https://example.com/book#secret", "book?access_token=secret", "book#secret"] {
            #expect(reading(sourceId: identifier) == nil)
            #expect(reading(mangaId: identifier) == nil)
            #expect(reading(chapterId: identifier) == nil)
            #expect(!HonbakoAutomationPolicy.validItem(.init(sourceId: "en.example", mangaId: identifier)))
        }
        #expect(reading(mangaId: "/manga/123", chapterId: "chapters/456") != nil,
                "Legitimate source path IDs remain usable; route IDs have a stricter separate policy")
        #expect(reading(mangaId: "https://example.com/manga/123") != nil)
    }

    @Test("Unknown actions and jobs outside executable queue states fail closed")
    func unsupportedJobsCannotExecute() {
        for kind in ["library.remove", "reader.jump", "system.exec", "questions.answer", "", "CATALOG.SEARCH"] {
            #expect(throws: HonbakoAutomationPolicy.Failure.self) {
                try HonbakoAutomationPolicy.validate(job(kind: kind))
            }
        }
        for status in ["running", "completed", "cancelled", "failed", "", "QUEUED"] {
            #expect(throws: HonbakoAutomationPolicy.Failure.self) {
                try HonbakoAutomationPolicy.validate(job(status: status))
            }
        }
        for identifier in ["../job", "job/another", "job?token=secret"] {
            #expect(throws: HonbakoAutomationPolicy.Failure.self) {
                try HonbakoAutomationPolicy.validate(job(id: identifier))
            }
        }
    }

    @Test("Catalog searches are bounded and cannot smuggle library mutation arguments")
    func searchPayloadLimits() throws {
        try HonbakoAutomationPolicy.validate(job(payload: .init(query: "rain", sourceIds: ["en.example"], limit: 20)))
        let invalid: [Models.Payload] = [
            .init(query: ""), .init(query: "   "), .init(query: "rain\nadmin"),
            .init(query: String(repeating: "x", count: 301)), .init(query: "rain", limit: 0),
            .init(query: "rain", limit: 21), .init(query: "rain", sourceIds: []),
            .init(query: "rain", sourceIds: [""]),
            .init(query: "rain", items: [.init(sourceId: "en.example", mangaId: "book")]),
            .init(query: "rain", idempotencyKey: "mutation_1")
        ]
        for payload in invalid {
            #expect(throws: HonbakoAutomationPolicy.Failure.self) {
                try HonbakoAutomationPolicy.validate(job(payload: payload))
            }
        }
    }

    @Test("Removing books follows the same bounded selection rules as adding them")
    func removePayloadRequiresExplicitBoundedSelection() throws {
        let item = Models.Item(sourceId: "en.example", mangaId: "/manga/123")
        try HonbakoAutomationPolicy.validate(job(kind: "library.remove", payload: .init(items: [item], idempotencyKey: "remove_1")))
        for payload: Models.Payload in [.init(items: [item]), .init(items: [item, item], idempotencyKey: "remove_1"),
                                        .init(query: "rain", items: [item], idempotencyKey: "remove_1")] {
            #expect(throws: HonbakoAutomationPolicy.Failure.self) {
                try HonbakoAutomationPolicy.validate(job(kind: "library.remove", payload: payload))
            }
        }
    }

    @Test("Adding books requires a bounded distinct selection and a safe idempotency key")
    func addPayloadRequiresExplicitBoundedSelection() throws {
        let item = Models.Item(sourceId: "en.example", mangaId: "/manga/123")
        try HonbakoAutomationPolicy.validate(job(kind: "library.add", payload: .init(items: [item], idempotencyKey: "add_123"), status: "awaitingApproval"))
        let tooMany = (0..<21).map { Models.Item(sourceId: "en.example", mangaId: "book-\($0)") }
        let invalid: [Models.Payload] = [
            .init(items: [], idempotencyKey: "add_123"), .init(items: [item]),
            .init(items: [item], idempotencyKey: "../other"), .init(items: [item, item], idempotencyKey: "add_123"),
            .init(items: tooMany, idempotencyKey: "add_123"),
            .init(items: [.init(sourceId: "", mangaId: "book")], idempotencyKey: "add_123"),
            .init(query: "rain", items: [item], idempotencyKey: "add_123"),
            .init(sourceIds: ["en.example"], items: [item], idempotencyKey: "add_123"),
            .init(limit: 1, items: [item], idempotencyKey: "add_123")
        ]
        for payload in invalid {
            #expect(throws: HonbakoAutomationPolicy.Failure.self) {
                try HonbakoAutomationPolicy.validate(job(kind: "library.add", payload: payload))
            }
        }
    }

    @Test("Malformed device jobs cannot decode into actionable commands")
    func malformedWireJobsAreRejected() {
        let invalid = [
            #"{}"#,
            #"{"id":"job_1","kind":"catalog.search","status":"queued","createdAt":"2026-10-29"}"#,
            #"{"id":"job_1","kind":"catalog.search","payload":null,"status":"queued","createdAt":"2026-10-29"}"#,
            #"{"id":"job_1","kind":"catalog.search","payload":{"query":42},"status":"queued","createdAt":"2026-10-29"}"#,
            #"{"id":"job_1","kind":"catalog.search","payload":{"query":"rain","limit":true},"status":"queued","createdAt":"2026-10-29"}"#,
            #"{"id":"job_1","kind":"library.add","payload":{"items":["book"],"idempotencyKey":"add_1"},"status":"queued","createdAt":"2026-10-29"}"#
        ]
        for wire in invalid {
            #expect(throws: (any Error).self) {
                _ = try JSONDecoder().decode(Models.Job.self, from: Data(wire.utf8))
            }
        }
    }

    @Test("Exported device state has a metadata allowlist and explicitly clears absent reading context")
    func exportedMetadataIsExplicitAndReadingNullClearsStaleContext() throws {
        let state = Models.State(generatedAt: timestamp,
            library: [.init(sourceId: "en.example", mangaId: "book", title: "A Book", author: "An Author", lastReadPage: 3)],
            sources: [.init(id: "en.example", name: "Personal Library", supportsSearch: true)], reading: try #require(reading()))
        let data = try JSONEncoder().encode(state)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let sources = try #require(object["sources"] as? [[String: Any]])
        let source = try #require(sources.first)
        #expect(Set(source.keys) == ["id", "name", "supportsSearch"])
        let current = try #require(object["reading"] as? [String: Any])
        let permitted: Set<String> = ["sourceId", "mangaId", "title", "chapterId", "chapterTitle", "chapterNumber",
                                      "volumeNumber", "page", "totalPages", "lastVisiblePage", "updatedAt", "active"]
        #expect(Set(current.keys).isSubset(of: permitted))
        let library = try #require(object["library"] as? [[String: Any]])
        let libraryItem = try #require(library.first)
        #expect(Set(libraryItem.keys) == ["sourceId", "mangaId", "title", "author", "lastReadPage"])
        for forbidden in ["headers", "cookies", "authorization", "password", "deviceToken", "coverURL", "archiveURL"] {
            #expect(current[forbidden] == nil && source[forbidden] == nil)
        }
        let idle = Models.State(generatedAt: timestamp, library: [], sources: [], reading: nil)
        let idleObject = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(idle)) as? [String: Any])
        #expect(idleObject["reading"] is NSNull, "Omitting the key would leave an old chapter active on the agent")
    }

    private func reading(sourceId: String = "en.example", mangaId: String = "book", chapterId: String = "chapter-1",
                         page: Int = 3, total: Int? = 20, visible: Int? = 4,
                         chapterNumber: Float? = 1, volumeNumber: Float? = 1) -> Models.Reading? {
        HonbakoAutomationPolicy.reading(sourceId: sourceId, mangaId: mangaId, title: "A Book",
            chapterId: chapterId, chapterTitle: "A Chapter", chapterNumber: chapterNumber, volumeNumber: volumeNumber,
            page: page, totalPages: total, lastVisiblePage: visible, updatedAt: timestamp, active: true)
    }

    private func job(id: String = "job_123", kind: String = "catalog.search", payload: Models.Payload = .init(query: "rain"),
                     status: String = "queued") -> Models.Job {
        .init(id: id, kind: kind, payload: payload, status: status, createdAt: timestamp)
    }
}
