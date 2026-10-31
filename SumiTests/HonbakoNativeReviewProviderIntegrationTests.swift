// Add this file to the simulator-only test target for the dedicated fixture run.
// HONBAKO_REVIEW_FIXTURE_ROOT points at this Tools/reviewer-fixtures directory.
// HONBAKO_REVIEW_FIXTURE_REMOTE=1 opts into the three exact review HTTPS hosts.
// HONBAKO_REVIEW_CREDENTIALS_FILENAME optionally selects a basename in runtime/.
// It intentionally stays outside active app/test targets until coordinated.
#if targetEnvironment(simulator)
@testable import Sumi
import AidokuRunner
import CryptoKit
import Foundation
import Testing
import UIKit

@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["HONBAKO_REVIEW_FIXTURE_ROOT"] != nil))
struct HonbakoNativeReviewProviderIntegrationTests {
    @Test("Real provider adapters authenticate, search, enumerate chapters, and decode every original page", arguments: ["komga", "kavita", "suwayomi"])
    func nativeProvider(_ provider: String) async throws {
        do {
            try await verifyNativeProvider(provider)
        } catch {
            // Provider image URLs may contain API-key queries. Never record the
            // raw thrown error, URLRequest, credential DTO, or underlying URL.
            Issue.record("Native provider verification failed; sensitive network details withheld.")
        }
    }

    private func verifyNativeProvider(_ provider: String) async throws {
        let environment = ProcessInfo.processInfo.environment
        let remote = environment["HONBAKO_REVIEW_FIXTURE_REMOTE"] == "1"
        let path = try #require(ProcessInfo.processInfo.environment["HONBAKO_REVIEW_FIXTURE_ROOT"])
        let root = URL(fileURLWithPath: path, isDirectory: true)
        let filename = environment["HONBAKO_REVIEW_CREDENTIALS_FILENAME"]
            ?? (remote ? "vm-native-credentials.json" : "credentials.json")
        try #require(!filename.isEmpty && filename == URL(fileURLWithPath: filename).lastPathComponent)
        try #require(!filename.contains("/") && !filename.contains("\\") && filename.hasSuffix(".json"))
        let credentialData = try Data(contentsOf: root.appendingPathComponent("runtime").appendingPathComponent(filename))
        let credentials = try JSONDecoder().decode([String: Accounts].self, from: credentialData)
        let accounts = try #require(credentials[provider])
        let account = accounts.reviewer
        let key = "honbako-review-fixture-\(provider)-\(UUID().uuidString)"
        let defaults = UserDefaults.standard
        defer {
            for name in defaults.dictionaryRepresentation().keys where name.hasPrefix(key + ".") { defaults.removeObject(forKey: name) }
        }
        let port: Int
        let title: String
        let source: AidokuRunner.Source
        switch provider {
        case "komga": port = 39101; title = "Your Collections"
        case "kavita": port = 39102; title = "Read Your Way"
        default: port = 39104; title = "Search & Delete"
        }
        let server: URL
        if remote {
            let address = try #require(accounts.server)
            let components = try #require(URLComponents(string: address))
            try #require(components.scheme == "https")
            try #require(components.host == provider + "-review.honbako.xyz")
            try #require(components.port == nil && components.user == nil && components.password == nil)
            try #require(components.query == nil && components.fragment == nil)
            try #require(components.path.isEmpty || components.path == "/")
            server = try #require(components.url)
        } else {
            // A remote credential file cannot silently redirect a legacy local run.
            try #require(accounts.server == nil)
            server = try #require(URL(string: "http://127.0.0.1:\(port)/"))
        }
        defaults.set(server.absoluteString, forKey: key + ".server")
        if provider == "kavita" {
            let response = await KavitaSourceRunner.getLoginResponse(
                server: server, username: account.username, password: account.password
            )
            let login = try #require(response)
            defaults.set(try #require(login.token), forKey: key + ".token")
            defaults.set(login.refreshToken, forKey: key + ".refreshToken")
            defaults.set(try #require(login.getApiKey()), forKey: key + ".apiKey")
            source = .kavita(key: key, name: "Original review", server: server.absoluteString)
        } else {
            defaults.set(account.username, forKey: key + ".login.username")
            defaults.set(account.password, forKey: key + ".login.password")
            if provider == "komga" {
                source = .komga(key: key, name: "Original review", server: server.absoluteString)
            } else {
                let login = await SuwayomiHelper.checkLogin(server: server, username: account.username, password: account.password)
                try #require(login != nil, "The real gateway must support the app's Basic authentication discovery")
                source = .suwayomi(key: key, name: "Original review", server: server.absoluteString)
            }
        }
        let result = try await source.getSearchMangaList(query: title, page: 1, filters: [])
        let book = try #require(result.entries.first { $0.title == title })
        let updated = try await source.getMangaUpdate(manga: book, needsDetails: true, needsChapters: true)
        let chapters = try #require(updated.chapters)
        #expect(chapters.count == 1)
        let pages = try await source.getPageList(manga: updated, chapter: try #require(chapters.first))
        #expect(pages.count == 5)
        let manifestURL = root.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("AppStore/review/build73/reviewer-fixtures.json")
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        let expected = Set(try #require(manifest.books.first { $0.provider == provider }).asset_sha256.values)
        var received: Set<String> = []
        for page in pages {
            guard case .url(let url, _) = page.content else { Issue.record("Expected a real provider image URL"); continue }
            let request = await source.getModifiedImageRequest(url: url, context: nil)
            try verifyImageOrigin(request, server: server, remote: remote)
            let (data, response) = try await URLSession.shared.data(for: request)
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
            let image = try #require(UIImage(data: data))
            #expect(image.size == CGSize(width: 1024, height: 1536))
            received.insert(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
        }
        #expect(received == expected, "Every native adapter must return the exact original CBZ page set")
        let cover = try #require(updated.cover.flatMap(URL.init(string:)))
        let request = await source.getModifiedImageRequest(url: cover, context: nil)
        try verifyImageOrigin(request, server: server, remote: remote)
        let (data, response) = try await URLSession.shared.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(UIImage(data: data) != nil)
    }

    private func verifyImageOrigin(_ request: URLRequest, server: URL, remote: Bool) throws {
        guard remote else { return }
        let address = try #require(request.url)
        try #require(address.scheme == "https" && address.host == server.host)
        try #require(address.port == nil && address.user == nil && address.password == nil)
    }

    private struct Accounts: Decodable { let reviewer: Account; let server: String? }
    private struct Account: Decodable { let username: String; let password: String }
    private struct Manifest: Decodable { let books: [Book] }
    private struct Book: Decodable { let provider: String; let asset_sha256: [String: String] }
}
#endif
