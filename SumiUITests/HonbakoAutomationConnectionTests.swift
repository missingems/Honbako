import Foundation
import UIKit
import XCTest

/// Explicit isolated-simulator integration. Ordinary runs never need a bridge.
final class HonbakoAutomationConnectionTests: XCTestCase {
    @MainActor
    func testPairReadingContextAndApprovedCatalogJobsThroughMCP() async throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("This integration uses the private capture simulator and an isolated loopback bridge.")
        #else
        let configuration = try Configuration.environment()
        let bridge = Bridge(configuration)
        defer { bridge.close() }
        try await bridge.initialize()
        let initial = try await bridge.tool("honbako_get_status")
        try require((initial["devices"] as? [[String: Any]])?.isEmpty == true,
                    "The integration bridge must start without paired devices")
        continueAfterFailure = true
        let previousOrientation = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.launchArguments = ["--sumi-grid-check", "--sumi-grid-reading-mode=rtl", "--honbako-automation-check",
                               "--honbako-catalog-check", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = previousOrientation }
        var deviceID: String?
        do {
            let grid = item("Sumi.Grid", app)
            try require(grid.waitForExistence(timeout: 20), "The generated fixture library must load")
            try openConnections(app)
            let oldConnection = app.buttons["Honbako.Automation.Disconnect"]
            if oldConnection.exists {
                // A previous failed isolated run revoked its fake server device.
                // Clear only this private simulator's native paired state via UI.
                try tap(oldConnection, in: app, direction: .towardTop)
                try require(app.buttons["Honbako.Automation.Connect"].waitForExistence(timeout: 10),
                            "The stale isolated connection must be cleared before pairing again")
            }
            let endpoint = app.textFields["Honbako.Automation.Endpoint"]
            try require(endpoint.waitForExistence(timeout: 5), "The isolated simulator must begin unpaired")
            try tap(endpoint, in: app)
            if let oldValue = endpoint.value as? String, oldValue != endpoint.placeholderValue, !oldValue.isEmpty {
                endpoint.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldValue.count))
            }
            endpoint.typeText(configuration.endpoint.absoluteString)
            let code = app.secureTextFields["Honbako.Automation.Code"]
            try tap(code, in: app, direction: nil)
            code.typeText(configuration.pairCode)
            let keyboardDone = app.keyboards.buttons.matching(NSPredicate(format: "label IN %@", ["Return", "Go", "Done"])).firstMatch
            if keyboardDone.exists, keyboardDone.isHittable { keyboardDone.tap() }
            try tap(app.buttons["Honbako.Automation.Connect"], in: app)
            try require(app.buttons["Honbako.Automation.Disconnect"].waitForExistence(timeout: 25),
                        "Pairing through the real form must connect the app")
            let paired = try await eventually("The paired device must appear through MCP") {
                let status = try await bridge.tool("honbako_get_status")
                guard let devices = status["devices"] as? [[String: Any]], devices.count == 1,
                      devices[0]["snapshotFresh"] as? Bool == true,
                      let identifier = devices[0]["deviceId"] as? String else { return nil }
                return ["deviceId": identifier]
            }
            let identifier = try string(paired, "deviceId")
            deviceID = identifier
            let status = item("Honbako.Automation.Status", app)
            try reveal(status, in: app, direction: .towardTop)
            _ = try await eventually("The native connection status must confirm the first completed sync") {
                guard status.exists, status.label.contains("Connected") else { return nil }
                return ["connected": true]
            }
            try setSharing(true, app)
            try closeSettings(app)
            try require(grid.waitForExistence(timeout: 8), "Closing Settings must return to the library")
            // This fixture has a real resumed bookmark: chapter 2, page 4.
            // Open its Reading entry in portrait, then verify its landscape spread.
            try tap(app.buttons["Sumi.Grid.Book.sumi-grid-preview:book-002"], in: app)
            let reader = item("Sumi.DirectReader", app)
            try require(reader.waitForExistence(timeout: 20), "The resumed generated reader must actually open")
            try rotate(.landscapeLeft, landscape: true, app)
            let window = try activeWindow(app, containing: reader.frame)
            try require(window.frame.width > window.frame.height, "This case requires a real landscape spread")
            // Rotation preserves the selected page 4 instead of moving the
            // bookmark to the preceding leaf of its 3–4 spread.
            var lastObservedContext: [String: Any]?
            let context: [String: Any]
            do {
                context = try await eventually("The actual reader must preserve its resumed canonical page through rotation") {
                    let result = try await bridge.tool("honbako_get_reading_context", ["deviceId": identifier])
                    lastObservedContext = result
                    guard let reading = result["reading"] as? [String: Any],
                          reading["title"] as? String == "Fixture Manga 002",
                          reading["page"] as? Int == 4, reading["lastVisiblePage"] as? Int == 4,
                          reading["active"] as? Bool == true else { return nil }
                    return result
                }
            } catch {
                // Capture only metadata from this isolated fake bridge, never configuration credentials.
                if let lastObservedContext, !containsSensitiveKey(lastObservedContext),
                   let data = try? JSONSerialization.data(withJSONObject: lastObservedContext, options: [.prettyPrinted, .sortedKeys]) {
                    let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                    attachment.name = "Last observed isolated MCP reading context"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
                let attachment = XCTAttachment(string: "Reader value: \(String(describing: reader.value))\n\(reader.debugDescription)")
                attachment.name = "Reader state at MCP context timeout"
                attachment.lifetime = .keepAlways
                add(attachment)
                throw error
            }
            let reading = try dictionary(context, "reading")
            try require(reading["sourceId"] as? String == "sumi-grid-preview", "Reading source identity must be exact")
            try require(reading["mangaId"] as? String == "book-002", "Reading book identity must be exact")
            try require(reading["chapterId"] as? String == "chapter-2", "Reading chapter must be the resumed canonical chapter 2")
            try require(reading["chapterNumber"] as? Int == 2, "Chapter number must be shared")
            try require(reading["chapterTitle"] as? String == "Fixture chapter 2", "Chapter title must be shared")
            try require(reading["totalPages"] as? Int == 8, "Reading total must come from actual generated pages")
            try require(context["observation"] as? String == "current", "An open reader must be current, not stale")
            let boundary = try dictionary(context, "spoilerBoundary")
            try require(boundary["chapterId"] as? String == "chapter-2" && boundary["page"] as? Int == 4
                        && boundary["lastVisiblePage"] as? Int == 4, "The spoiler boundary must stop at the preserved reading page")
            let allowed: Set<String> = ["sourceId", "mangaId", "title", "chapterId", "chapterTitle", "chapterNumber",
                                        "volumeNumber", "page", "totalPages", "lastVisiblePage", "updatedAt", "active"]
            try require(Set(reading.keys).isSubset(of: allowed), "Only approved reading metadata may leave the app")
            try require(!containsSensitiveKey(context), "Reading context must not export credentials, cookies, or page images")
            try closeReader(app)
            _ = try await eventually("Closing a book must mark its published reading context inactive") {
                let result = try await bridge.tool("honbako_get_reading_context", ["deviceId": identifier])
                guard let reading = result["reading"] as? [String: Any], reading["active"] as? Bool == false,
                      reading["mangaId"] as? String == "book-002", result["observation"] as? String == "last_known" else { return nil }
                return result
            }
            try rotate(.portrait, landscape: false, app)
            try openConnections(app)
            try setSharing(false, app)
            _ = try await eventually("Disabling sharing must clear remote reading context explicitly") {
                let result = try await bridge.tool("honbako_get_reading_context", ["deviceId": identifier])
                return result["reading"] is NSNull ? result : nil
            }
            try await exerciseCatalogApproval(app, bridge: bridge, deviceID: identifier)
            try tap(app.buttons["Honbako.Automation.Disconnect"], in: app, direction: .towardTop)
            try require(app.buttons["Honbako.Automation.Connect"].waitForExistence(timeout: 10), "Disconnect must clear native pairing")
            _ = try await eventually("Disconnect must delete the paired device on the bridge") {
                let result = try await bridge.tool("honbako_get_status")
                return (result["devices"] as? [[String: Any]])?.isEmpty == true ? result : nil
            }
            deviceID = nil
        } catch {
            // Only this test's freshly paired device on its verified loopback server.
            if let deviceID { try? await bridge.forget(deviceID) }
            throw error
        }
        #endif
    }

    @MainActor
    private func exerciseCatalogApproval(_ app: XCUIApplication, bridge: Bridge, deviceID: String) async throws {
        _ = try await eventually("The app must publish its already-connected generated catalog") {
            let result = try await bridge.tool("honbako_list_sources", ["deviceId": deviceID])
            guard let sources = result["sources"] as? [[String: Any]],
                  sources.contains(where: { $0["id"] as? String == "honbako-catalog-fast" && $0["supportsSearch"] as? Bool == true }) else { return nil }
            return result
        }
        let source = "honbako-catalog-fast", manga = "book-024"
        let initial = try await bridge.tool("honbako_search_library", ["deviceId": deviceID, "query": "Fixture Manga 024"])
        let initialCount = matching(initial, source: source, manga: manga).count
        try require(initialCount <= 1, "The isolated generated title must not start duplicated")
        let search = try await bridge.tool("honbako_search_catalog",
            ["deviceId": deviceID, "query": "024", "sourceIds": [source], "limit": 20])
        let searchID = try string(search, "id")
        let searched = try await job(searchID, status: "completed", bridge: bridge, deviceID: deviceID)
        let result = try dictionary(searched, "result")
        let found = matching(result, source: source, manga: manga)
        try require(found.count == 1 && found[0]["title"] as? String == "Fixture Manga 024",
                    "The native job must return the exact generated catalog match")
        let items = [["sourceId": source, "mangaId": manga]]
        let rejected = try await bridge.tool("honbako_add_to_library",
            ["deviceId": deviceID, "items": items, "idempotencyKey": "reject_" + UUID().uuidString])
        let rejectedID = try string(rejected, "id")
        _ = try await job(rejectedID, status: "awaitingApproval", bridge: bridge, deviceID: deviceID)
        try tap(item("Honbako.Automation.Request.\(rejectedID)", app), in: app)
        try require(app.staticTexts["Fixture Manga 024"].waitForExistence(timeout: 5), "Approval must show the actual selected book")
        try tap(app.buttons["Honbako.Automation.Reject.\(rejectedID)"], in: app)
        _ = try await job(rejectedID, status: "rejected", bridge: bridge, deviceID: deviceID)
        let unchanged = try await bridge.tool("honbako_search_library", ["deviceId": deviceID, "query": "Fixture Manga 024"])
        try require(matching(unchanged, source: source, manga: manga).count == initialCount, "Rejecting must not add a book")
        let key = "approve_" + UUID().uuidString
        let approved = try await bridge.tool("honbako_add_to_library", ["deviceId": deviceID, "items": items, "idempotencyKey": key])
        let approvedID = try string(approved, "id")
        _ = try await job(approvedID, status: "awaitingApproval", bridge: bridge, deviceID: deviceID)
        try tap(item("Honbako.Automation.Request.\(approvedID)", app), in: app)
        try require(app.staticTexts["Fixture Manga 024"].waitForExistence(timeout: 5), "The second approval preview must name the same exact book")
        try tap(app.buttons["Honbako.Automation.Approve.\(approvedID)"], in: app)
        let completed = try await job(approvedID, status: "completed", bridge: bridge, deviceID: deviceID)
        let added = try dictionary(completed, "result")
        let receipts = ((added["added"] as? [[String: Any]]) ?? []) + ((added["alreadyPresent"] as? [[String: Any]]) ?? [])
        try require(receipts.filter { $0["sourceId"] as? String == source && $0["mangaId"] as? String == manga }.count == 1,
                    "The completed native addition must acknowledge exactly the selected identity")
        _ = try await eventually("Approved additions must appear once in the real synced saved library") {
            let snapshot = try await bridge.tool("honbako_search_library", ["deviceId": deviceID, "query": "Fixture Manga 024"])
            return self.matching(snapshot, source: source, manga: manga).count == 1 ? snapshot : nil
        }
        let retried = try await bridge.tool("honbako_add_to_library", ["deviceId": deviceID, "items": items, "idempotencyKey": key])
        try require(retried["id"] as? String == approvedID && retried["status"] as? String == "completed",
                    "Retrying the same addition must reuse its completed job")
        let once = try await bridge.tool("honbako_search_library", ["deviceId": deviceID, "query": "Fixture Manga 024"])
        try require(matching(once, source: source, manga: manga).count == 1, "Idempotent retries must not duplicate the saved title")
        try reveal(app.buttons["Honbako.Automation.Disconnect"], in: app, direction: .towardTop)
    }

    @MainActor
    private func rotate(_ orientation: UIDeviceOrientation, landscape: Bool, _ app: XCUIApplication) throws {
        XCUIDevice.shared.orientation = orientation
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.windows.allElementsBoundByIndex.contains {
                $0.isHittable && !$0.frame.isEmpty && ($0.frame.width > $0.frame.height) == landscape
            }
        }, object: nil)
        try require(XCTWaiter.wait(for: [settled], timeout: 10) == .completed,
                    "The active app window must reach the requested orientation")
    }

    @MainActor
    private func openConnections(_ app: XCUIApplication) throws {
        try tap(app.buttons["Honbako.Library.Settings"], in: app)
        try tap(item("Honbako.Automation", app), in: app)
        try require(item("Honbako.Automation.Status", app).waitForExistence(timeout: 5), "MCP Server must present its native form")
    }

    @MainActor
    private func closeSettings(_ app: XCUIApplication) throws {
        let connectionsBar = app.navigationBars["MCP Server"]
        if connectionsBar.exists {
            // Scope to the pushed view: an unscoped Settings button can resolve
            // to the library gear that remains underneath this modal sheet.
            let namedBack = connectionsBar.buttons["Back"].firstMatch
            let verticalBack = app.descendants(matching: .any).matching(identifier: "BackButton").firstMatch
            let back = namedBack.exists ? namedBack : (verticalBack.exists ? verticalBack : connectionsBar.buttons.element(boundBy: 0))
            try tap(back, in: app, direction: nil)
        }
        let settingsBar = app.navigationBars["Settings"]
        try require(settingsBar.waitForExistence(timeout: 5), "Back must return to the Settings sheet")
        try tap(settingsBar.buttons["Done"].firstMatch, in: app, direction: nil)
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let gear = app.buttons["Honbako.Library.Settings"]
            return !connectionsBar.exists && !settingsBar.exists && gear.exists && gear.isHittable
        }, object: nil)
        try require(XCTWaiter.wait(for: [dismissed], timeout: 8) == .completed,
                    "Settings must be dismissed and the library gear reachable before continuing")
    }

    @MainActor
    private func setSharing(_ enabled: Bool, _ app: XCUIApplication) throws {
        let toggle = app.switches["Honbako.Automation.ShareReading"]
        try reveal(toggle, in: app, direction: .towardBottom)
        if (toggle.value as? String == "1") != enabled {
            // SwiftUI exposes the entire labelled row as a Switch. Its empty
            // centre does not activate the native thumb at the trailing edge.
            let frame = toggle.frame
            let window = try activeWindow(app, containing: frame)
            let base = window.frame
            window.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: frame.maxX - 25 - base.minX, dy: frame.midY - base.minY)).tap()
        }
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", enabled ? "1" : "0"), object: toggle)
        try require(XCTWaiter.wait(for: [changed], timeout: 5) == .completed, "Reading sharing must match the requested state")
    }

    @MainActor
    private func closeReader(_ app: XCUIApplication) throws {
        let reader = item("Sumi.DirectReader", app)
        let close = app.buttons["SumiReader.Close"]
        if !close.exists || !close.isHittable {
            let renderer = item("sumi.reader.curl", app)
            try require(renderer.waitForExistence(timeout: 5), "The generated landscape reader must use the real curl renderer")
            renderer.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.4)).tap()
        }
        try tap(close, in: app, direction: nil)
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: reader)
        try require(XCTWaiter.wait(for: [expectation], timeout: 10) == .completed, "Closing must dismiss the generated reader")
    }

    private enum RevealDirection: Equatable { case towardTop, towardBottom }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, direction: RevealDirection?) throws {
        _ = element.waitForExistence(timeout: 0.8)
        if let direction {
            for _ in 0..<5 {
                if element.exists, element.isHittable { break }
                var towardTop = direction == .towardTop
                if element.exists, !element.frame.isEmpty,
                   let window = app.windows.allElementsBoundByIndex.first(where: { $0.isHittable }) {
                    if element.frame.maxY <= window.frame.minY + 90 { towardTop = true }
                    else if element.frame.minY >= window.frame.maxY - 40 { towardTop = false }
                }
                try scrollForm(app, towardTop: towardTop)
                _ = element.waitForExistence(timeout: 0.3)
            }
        }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: element)
        try require(XCTWaiter.wait(for: [ready], timeout: 5) == .completed, "The requested native control must appear and be reachable")
    }

    @MainActor
    private func scrollForm(_ app: XCUIApplication, towardTop: Bool) throws {
        // Application.swipeUp can retain portrait gesture coordinates while
        // the clone's window is landscape. Use that window's actual geometry.
        let candidates = app.collectionViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex
        let nativeForm = candidates.last(where: { $0.isHittable && $0.frame.height > 100 })
        let library = app.scrollViews["Sumi.Grid"]
        let scrolls = app.scrollViews.allElementsBoundByIndex
        let fallback = library.exists && library.isHittable ? library
            : scrolls.last(where: { $0.isHittable && $0.frame.height > 100 })
        guard let form = nativeForm ?? fallback else { throw Failure.invalidResponse }
        let window = try activeWindow(app, containing: form.frame)
        let base = window.frame
        var viewport = form.frame.intersection(base)
        let bars = app.navigationBars.allElementsBoundByIndex.filter { $0.isHittable }
        let top = max(viewport.minY + 12, bars.map { $0.frame.maxY + 10 }.max() ?? viewport.minY + 12)
        var bottom = viewport.maxY - 16
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists { bottom = min(bottom, keyboard.frame.minY - 10) }
        try require(bottom - top > 40, "The current scroll view must have a visible vertical scrolling region")
        viewport = CGRect(x: viewport.minX, y: top, width: viewport.width, height: bottom - top)
        let low = viewport.minY + viewport.height * 0.15
        let high = viewport.maxY - viewport.height * 0.15
        let origin = window.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: viewport.midX - base.minX, dy: (towardTop ? low : high) - base.minY))
        let end = origin.withOffset(CGVector(dx: viewport.midX - base.minX, dy: (towardTop ? high : low) - base.minY))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.05)
    }

    @MainActor
    private func tap(_ element: XCUIElement, in app: XCUIApplication, direction: RevealDirection? = .towardBottom) throws {
        try reveal(element, in: app, direction: direction)
        let frame = element.frame
        let window = try activeWindow(app, containing: frame)
        let base = window.frame
        window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX - base.minX, dy: frame.midY - base.minY)).tap()
    }

    @MainActor
    private func activeWindow(_ app: XCUIApplication, containing frame: CGRect) throws -> XCUIElement {
        guard let window = app.windows.allElementsBoundByIndex.first(where: {
            $0.isHittable && $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY))
        }) else { throw Failure.invalidResponse }
        return window
    }

    @MainActor
    private func item(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func matching(_ object: [String: Any], source: String, manga: String) -> [[String: Any]] {
        ((object["matches"] as? [[String: Any]]) ?? []).filter { $0["sourceId"] as? String == source && $0["mangaId"] as? String == manga }
    }
    private func containsSensitiveKey(_ value: Any) -> Bool {
        let forbidden: Set<String> = ["token", "devicetoken", "authorization", "password", "cookies", "cookie", "headers", "pageimages", "images", "coverurl", "archiveurl"]
        if let object = value as? [String: Any] {
            return object.contains { forbidden.contains($0.key.lowercased()) || containsSensitiveKey($0.value) }
        }
        if let array = value as? [Any] { return array.contains(where: containsSensitiveKey) }
        return false
    }
    private func require(_ condition: @autoclosure () -> Bool, _ message: String,
                         file: StaticString = #filePath, line: UInt = #line) throws {
        guard condition() else { XCTFail(message, file: file, line: line); throw Failure.assertion }
    }
    private func string(_ object: [String: Any], _ key: String) throws -> String {
        guard let value = object[key] as? String, !value.isEmpty else { throw Failure.invalidResponse }
        return value
    }
    private func dictionary(_ object: [String: Any], _ key: String) throws -> [String: Any] {
        guard let value = object[key] as? [String: Any] else { throw Failure.invalidResponse }
        return value
    }
    @MainActor
    private func eventually(_ message: String, timeout: TimeInterval = 35,
                            _ poll: () async throws -> [String: Any]?) async throws -> [String: Any] {
        let deadline = Date.now.addingTimeInterval(timeout)
        repeat {
            if let result = try await poll() { return result }
            try await Task.sleep(for: .milliseconds(500))
        } while Date.now < deadline
        XCTFail(message)
        throw Failure.timeout
    }
    @MainActor
    private func job(_ id: String, status: String, bridge: Bridge, deviceID: String) async throws -> [String: Any] {
        try await eventually("The native device job must reach \(status)") {
            let result = try await bridge.tool("honbako_get_job", ["deviceId": deviceID, "jobId": id])
            if ["failed", "rejected", "cancelled"].contains(result["status"] as? String ?? ""), result["status"] as? String != status {
                XCTFail("The native device job ended before its expected state")
                throw Failure.assertion
            }
            return result["status"] as? String == status ? result : nil
        }
    }

    private struct Configuration {
        let endpoint: URL
        let pairCode: String
        let token: String
        static func environment() throws -> Self {
            let env = ProcessInfo.processInfo.environment
            guard let address = env["HONBAKO_AUTOMATION_ENDPOINT"], let endpoint = URL(string: address),
                  let code = env["HONBAKO_AUTOMATION_PAIR_CODE"], code.count == 6, code.allSatisfy(\.isNumber),
                  let token = env["HONBAKO_AUTOMATION_MCP_TOKEN"], !token.isEmpty else {
                throw XCTSkip("Set the isolated bridge endpoint, one-time code and fake MCP token to run this integration.")
            }
            guard endpoint.scheme == "http", ["127.0.0.1", "localhost", "::1", "[::1]"].contains(endpoint.host ?? ""),
                  endpoint.user == nil, endpoint.password == nil, endpoint.query == nil, endpoint.fragment == nil else {
                throw XCTSkip("This integration is restricted to an isolated loopback bridge on the capture simulator.")
            }
            return .init(endpoint: endpoint, pairCode: code, token: token)
        }
    }
    private enum Failure: Error { case assertion, timeout, invalidResponse, http(Int), rpc }

    @MainActor
    private final class Bridge {
        private let configuration: Configuration
        private let session = URLSession(configuration: .ephemeral)
        private var counter = 0
        private var protocolVersion = "2025-11-25"
        init(_ configuration: Configuration) { self.configuration = configuration }
        func close() { session.invalidateAndCancel() }
        func initialize() async throws {
            let negotiated = try await rpc("initialize", ["protocolVersion": protocolVersion, "capabilities": [:],
                                                      "clientInfo": ["name": "HonbakoIsolatedUITests", "version": "1.0.0"]])
            guard let version = negotiated["protocolVersion"] as? String,
                  ["2025-11-25", "2025-06-18", "2024-11-05"].contains(version) else { throw Failure.rpc }
            protocolVersion = version
        }
        func tool(_ name: String, _ arguments: [String: Any] = [:]) async throws -> [String: Any] {
            let response = try await rpc("tools/call", ["name": name, "arguments": arguments])
            guard response["isError"] as? Bool != true else { throw Failure.rpc }
            if let structured = response["structuredContent"] as? [String: Any] { return structured }
            if let content = response["content"] as? [[String: Any]], let text = content.first?["text"] as? String,
               let result = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] { return result }
            throw Failure.invalidResponse
        }
        func forget(_ id: String) async throws {
            var request = URLRequest(url: configuration.endpoint.appendingPathComponent("api/admin/devices/\(id)"))
            request.httpMethod = "DELETE"
            request.setValue("Bearer " + configuration.token, forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 5
            _ = try await session.data(for: request)
        }
        private func rpc(_ method: String, _ parameters: [String: Any]) async throws -> [String: Any] {
            counter += 1
            var request = URLRequest(url: configuration.endpoint.appendingPathComponent("mcp"))
            request.httpMethod = "POST"
            request.timeoutInterval = 8
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
            request.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
            request.setValue("Bearer " + configuration.token, forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": counter, "method": method, "params": parameters])
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw Failure.invalidResponse }
            guard http.statusCode == 200 else { throw Failure.http(http.statusCode) }
            guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any], envelope["error"] == nil,
                  let result = envelope["result"] as? [String: Any] else { throw Failure.rpc }
            return result
        }
    }
}
