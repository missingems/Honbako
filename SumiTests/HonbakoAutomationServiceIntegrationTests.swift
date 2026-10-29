@testable import Sumi
import Foundation
import CoreData
import UIKit
import XCTest

/// Real native service and Core Data against the explicitly isolated Mac bridge.
final class HonbakoAutomationServiceIntegrationTests: XCTestCase {
    @MainActor
    func testNativePairReadingApprovalAndLibraryPipeline() async throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Private simulator and isolated loopback bridge only.")
        #else
        let env = ProcessInfo.processInfo.environment, arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--honbako-catalog-check"), arguments.contains("--honbako-automation-check"),
              let address = env["HONBAKO_AUTOMATION_ENDPOINT"], let endpoint = HonbakoAutomationPolicy.endpoint(address),
              endpoint.scheme == "http", ["127.0.0.1", "localhost", "::1", "[::1]"].contains(endpoint.host ?? ""),
              endpoint.port == 43188, endpoint.user == nil, endpoint.password == nil,
              endpoint.query == nil, endpoint.fragment == nil, ["", "/"].contains(endpoint.path),
              let code = env["HONBAKO_AUTOMATION_PAIR_CODE"], code.count == 6, code.allSatisfy(\.isNumber),
              let token = env["HONBAKO_AUTOMATION_MCP_TOKEN"], HonbakoAutomationPolicy.validDeviceToken(token)
        else { throw XCTSkip("Set fake bridge credentials, exact fixture flags, and loopback port 43188.") }
        let service = HonbakoAutomationService.shared, bridge = Bridge(endpoint: endpoint, token: token)
        guard service.endpoint.isEmpty || URL(string: service.endpoint) == endpoint else {
            throw XCTSkip("Never alter a simulator pairing outside this isolated test bridge.")
        }
        defer { bridge.close() }
        try await eventually("The test host must be foregrounded") { UIApplication.shared.applicationState == .active }
        if !service.endpoint.isEmpty { await service.disconnect() }
        let target = MangaIdentifier(sourceKey: "honbako-catalog-fast", mangaKey: "book-024")
        await MangaManager.shared.removeFromLibrary(mangaId: target)
        _ = await SourceManager.shared.getLoadedSources()
        try await bridge.initialize()
        try require((try await bridge.tool("honbako_get_status")["devices"] as? [[String: Any]])?.isEmpty == true,
                    "Start the isolated bridge with no paired devices")
        do {
            await service.connect(endpoint: address, code: code)
            try require(service.isEnabled, "Native pairing must succeed")
            var deviceID = ""
            try await eventually("Native initial snapshot must reach MCP") {
                let status = try await bridge.tool("honbako_get_status")
                guard let devices = status["devices"] as? [[String: Any]], devices.count == 1,
                      devices[0]["snapshotFresh"] as? Bool == true, let id = devices[0]["deviceId"] as? String else { return false }
                deviceID = id; return true
            }
            func tool(_ name: String, _ input: [String: Any] = [:]) async throws -> [String: Any] {
                try await bridge.tool(name, input.merging(["deviceId": deviceID]) { _, device in device })
            }
            service.setSharingReading(true)
            service.updateReading(sourceId: "sumi-grid-preview", mangaId: "book-001", title: "Fixture Manga 001",
                chapterId: "chapter-1", chapterTitle: "Fixture chapter 1", chapterNumber: 1,
                page: 3, totalPages: 8, lastVisiblePage: 4, active: true)
            try await eventually("Native canonical reading metadata must be current") {
                let context = try await tool("honbako_get_reading_context"), reading = context["reading"] as? [String: Any]
                let boundary = context["spoilerBoundary"] as? [String: Any]
                return reading?["page"] as? Int == 3 && reading?["lastVisiblePage"] as? Int == 4
                    && reading?["totalPages"] as? Int == 8 && reading?["mangaId"] as? String == "book-001"
                    && context["observation"] as? String == "current" && boundary?["lastVisiblePage"] as? Int == 4
            }
            service.markReadingInactive()
            try await eventually("Closed-reader context must be last known") {
                let context = try await tool("honbako_get_reading_context")
                return context["observation"] as? String == "last_known"
                    && (context["reading"] as? [String: Any])?["active"] as? Bool == false
            }
            service.setSharingReading(false)
            try await eventually("Turning sharing off must clear remote reading") {
                try await tool("honbako_get_reading_context")["reading"] is NSNull
            }
            let sources = try await tool("honbako_list_sources")["sources"] as? [[String: Any]] ?? []
            try require(sources.contains { $0["id"] as? String == target.sourceKey }, "Publish the actual Fast Catalog fixture")
            let search = try await tool("honbako_search_catalog", ["query": "024", "sourceIds": [target.sourceKey], "limit": 20])
            let searched = try await job(try identifier(search), status: "completed", bridge: bridge, device: deviceID)
            let matches = (searched["result"] as? [String: Any])?["matches"] as? [[String: Any]] ?? []
            try require(matches.contains { $0["mangaId"] as? String == target.mangaKey && $0["title"] as? String == "Fixture Manga 024" },
                        "Real native source search must return the requested generated title")
            let items = [["sourceId": target.sourceKey, "mangaId": target.mangaKey]]
            let rejected = try await tool("honbako_add_to_library", ["items": items, "idempotencyKey": "reject_" + UUID().uuidString])
            let rejectID = try identifier(rejected)
            try await eventually("Native preview must be prepared before rejection") { service.pendingApprovals.contains { $0.id == rejectID } }
            try require(await count(target) == 0, "Preparing approval must never add a book")
            await service.reject(jobID: rejectID)
            _ = try await job(rejectID, status: "rejected", bridge: bridge, device: deviceID)
            try require(await count(target) == 0, "Rejecting must leave the real library unchanged")
            let key = "approve_" + UUID().uuidString
            let approved = try await tool("honbako_add_to_library", ["items": items, "idempotencyKey": key])
            let approveID = try identifier(approved)
            try await eventually("Native approval must expose the exact title") {
                service.pendingApprovals.contains { $0.id == approveID && $0.items.first?.title == "Fixture Manga 024" }
            }
            service.approve(jobID: approveID)
            let completed = try await job(approveID, status: "completed", bridge: bridge, device: deviceID)
            let result = completed["result"] as? [String: Any], added = result?["added"] as? [[String: Any]] ?? []
            try require(added.count == 1 && added.first?["mangaId"] as? String == target.mangaKey, "Approve must perform and receipt a real addition")
            try require(await count(target) == 1, "Core Data must contain exactly one approved book")
            let retry = try await tool("honbako_add_to_library", ["items": items, "idempotencyKey": key])
            try require(try identifier(retry) == approveID && retry["status"] as? String == "completed", "Same-key retries must reuse the completed job")
            try require(await count(target) == 1, "Retry must not duplicate the saved book")
            // Seed only this generated book's history to prove page-history redaction too.
            try await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.setProgress(3, chapterId: .init(sourceKey: target.sourceKey, mangaKey: target.mangaKey, chapterKey: "chapter-1"), totalPages: 4, context: context)
                try context.save()
            }
            NotificationCenter.default.post(name: .updateLibrary, object: nil)
            service.setSharingReading(true)
            try await eventually("Opted-in library metadata must include real generated history") {
                let saved = try await tool("honbako_search_library", ["query": "Fixture Manga 024"])["matches"] as? [[String: Any]] ?? []
                return saved.first?["lastReadPage"] as? Int == 3
            }
            service.setSharingReading(false)
            try await eventually("Opting out must remove reading and every per-book page field") {
                let context = try await tool("honbako_get_reading_context")
                let saved = try await tool("honbako_search_library", ["query": "Fixture Manga 024"])["matches"] as? [[String: Any]] ?? []
                return context["reading"] is NSNull && saved.count == 1 && saved.allSatisfy { $0["lastReadPage"] == nil }
            }
            await service.disconnect()
            try require(!service.isEnabled, "Disconnect must disable the native service")
            try await eventually("Disconnect must delete and revoke this fake paired device") {
                (try await bridge.tool("honbako_get_status")["devices"] as? [[String: Any]])?.isEmpty == true
            }
        } catch {
            if URL(string: service.endpoint) == endpoint { await service.disconnect() }
            await MangaManager.shared.removeFromLibrary(mangaId: target)
            throw error
        }
        await MangaManager.shared.removeFromLibrary(mangaId: target)
        #endif
    }

    @MainActor private func count(_ id: MangaIdentifier) async -> Int {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getLibraryManga(context: context).filter { $0.manga?.identifier == id }.count
        }
    }
    private func require(_ condition: Bool, _ message: String) throws {
        if !condition { XCTFail(message); throw Failure.invalid }
    }
    private func identifier(_ value: [String: Any]) throws -> String {
        guard let id = value["id"] as? String else { throw Failure.invalid }; return id
    }
    @MainActor private func eventually(_ message: String, _ condition: @MainActor () async throws -> Bool) async throws {
        let deadline = Date.now.addingTimeInterval(35)
        repeat { if try await condition() { return }; try await Task.sleep(for: .milliseconds(400)) } while Date.now < deadline
        XCTFail(message); throw Failure.timeout
    }
    @MainActor private func job(_ id: String, status: String, bridge: Bridge, device: String) async throws -> [String: Any] {
        var result: [String: Any] = [:]
        try await eventually("Native job must reach " + status) {
            result = try await bridge.tool("honbako_get_job", ["deviceId": device, "jobId": id])
            if ["failed", "cancelled", "rejected"].contains(result["status"] as? String ?? ""), result["status"] as? String != status { throw Failure.invalid }
            return result["status"] as? String == status
        }; return result
    }
    private enum Failure: Error { case invalid, timeout }
    @MainActor private final class Bridge {
        let endpoint: URL, token: String
        var counter = 0
        let session = URLSession(configuration: .ephemeral)
        init(endpoint: URL, token: String) { self.endpoint = endpoint; self.token = token }
        func close() { session.invalidateAndCancel() }
        func initialize() async throws {
            _ = try await rpc("initialize", ["protocolVersion": "2025-11-25", "capabilities": [:], "clientInfo": ["name": "HonbakoNativeServiceTest", "version": "1"]])
        }
        func tool(_ name: String, _ input: [String: Any] = [:]) async throws -> [String: Any] {
            let result = try await rpc("tools/call", ["name": name, "arguments": input])
            guard result["isError"] as? Bool != true, let value = result["structuredContent"] as? [String: Any] else { throw Failure.invalid }; return value
        }
        func rpc(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
            counter += 1
            var request = URLRequest(url: endpoint.appendingPathComponent("mcp"))
            request.httpMethod = "POST"; request.timeoutInterval = 8
            for (key, value) in ["Content-Type": "application/json", "Accept": "application/json, text/event-stream", "MCP-Protocol-Version": "2025-11-25", "Authorization": "Bearer " + token] { request.setValue(value, forHTTPHeaderField: key) }
            request.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": counter, "method": method, "params": params])
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  envelope["error"] == nil, let result = envelope["result"] as? [String: Any] else { throw Failure.invalid }; return result
        }
    }
}
