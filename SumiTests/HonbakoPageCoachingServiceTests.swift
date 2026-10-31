@testable import Sumi
import Foundation
import Testing
import UIKit

@MainActor
@Suite struct HonbakoPageCoachingServiceTests {
    @Test("An image taking longer than the session tick loads once instead of restarting forever")
    func slowImageLoadFinishes() async throws {
        let fixture = CoachingServiceFixture()
        defer { fixture.close() }
        fixture.probe.holdImages = true
        try fixture.start()
        try await coachingEventually { fixture.probe.imageLoads == 1 }
        try await Task.sleep(for: .milliseconds(900))
        #expect(fixture.probe.imageLoads == 1)
        #expect(fixture.probe.uploads.isEmpty)
        fixture.probe.releaseImages()
        try await coachingEventually { fixture.probe.uploads.count == 1 }
        #expect(fixture.service.currentPage?.page.page == 1)
    }

    @Test("While the server is refusing requests, the session tick sends nothing, then resumes")
    func rateLimitPausesSharing() async throws {
        let fixture = CoachingServiceFixture()
        defer { fixture.close() }
        try fixture.start()
        try await coachingEventually { fixture.probe.getRequests >= 1 }
        fixture.probe.limitedUntil = fixture.probe.now.addingTimeInterval(60)
        try await Task.sleep(for: .milliseconds(100))
        let uploads = fixture.probe.uploads.count, polls = fixture.probe.getRequests
        try await Task.sleep(for: .milliseconds(1600))
        #expect(fixture.probe.uploads.count == uploads)
        #expect(fixture.probe.getRequests == polls, "Two session ticks passed without a request")
        fixture.probe.now = fixture.probe.now.addingTimeInterval(61)
        try await coachingEventually { fixture.probe.getRequests > polls }
    }

    @Test("With jobs-poll summaries, drawings are fetched only when the summary changes")
    func summariesGateDrawingFetches() async throws {
        let fixture = CoachingServiceFixture()
        defer { fixture.close() }
        try fixture.start()
        try await coachingEventually { fixture.probe.getRequests >= 1 }
        let page = try #require(fixture.service.currentPage)
        let summary = HonbakoPageCoachingModels.Summary(active: true, sessionId: page.sessionId,
            pageGeneration: page.pageGeneration, pageId: page.page.pageId, annotationRevision: 1)
        fixture.service.receive(summary)
        try await Task.sleep(for: .milliseconds(900))
        let settled = fixture.probe.getRequests
        for _ in 0..<3 {
            fixture.service.receive(summary)
            fixture.service.refreshVisiblePage()
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(800))
        #expect(fixture.probe.getRequests == settled, "An unchanged summary fetches nothing")
        var drawn = summary
        drawn.annotationRevision = 2
        fixture.service.receive(drawn)
        fixture.service.refreshVisiblePage()
        try await coachingEventually { fixture.probe.getRequests == settled + 1 }
        try await Task.sleep(for: .milliseconds(800))
        #expect(fixture.probe.getRequests == settled + 1, "A changed summary fetches once")
        fixture.service.receive(nil)
        try await coachingEventually { fixture.probe.getRequests >= settled + 3 }
    }

    @Test("With images on request, pages go up as details only and the image follows once when asked")
    func imagesGoUpOnlyWhenAsked() async throws {
        typealias Summary = HonbakoPageCoachingModels.Summary
        let fixture = CoachingServiceFixture()
        defer { fixture.close() }
        fixture.service.receive(Summary(active: false, sessionId: nil, reason: "not_shared", imagesOnRequest: true))
        try fixture.start()
        try await coachingEventually { fixture.probe.uploads.count == 1 }
        #expect(fixture.probe.uploads[0].image == nil, "Turning to a page sends no pixels")
        let page = try #require(fixture.service.currentPage)
        let asked = Summary(active: true, sessionId: page.sessionId, pageGeneration: page.pageGeneration,
            pageId: page.page.pageId, annotationRevision: 0, imagesOnRequest: true, imageRequested: true)
        try await coachingEventually {
            fixture.service.receive(asked)
            fixture.service.refreshVisiblePage()
            return fixture.probe.uploads.count == 2
        }
        #expect(fixture.probe.uploads[1].image != nil)
        #expect(fixture.probe.uploads[1].pageGeneration == page.pageGeneration)
        for _ in 0..<3 {
            fixture.service.receive(asked)
            fixture.service.refreshVisiblePage()
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(800))
        #expect(fixture.probe.uploads.count == 2, "One request uploads the image once")
    }

    @Test("A reader waits for the server's image policy, and an older server still gets images")
    func readerWaitsForImagePolicy() async throws {
        let fixture = CoachingServiceFixture(waitsForImagePolicy: true)
        defer { fixture.close() }
        try fixture.start()
        try await Task.sleep(for: .milliseconds(900))
        #expect(fixture.probe.uploads.isEmpty, "Nothing goes up before the server says how it takes images")
        fixture.service.receive(nil)
        try await coachingEventually { fixture.probe.uploads.count == 1 }
        #expect(fixture.probe.uploads[0].image != nil)
    }

    @Test("A stream the server closed starts a fresh session instead of retrying the dead one")
    func closedStreamStartsFreshSession() async throws {
        let fixture = CoachingServiceFixture()
        defer { fixture.close() }
        fixture.probe.closeNextPost = true
        try fixture.start()
        try await coachingEventually { fixture.probe.uploads.count == 2 }
        let first = fixture.probe.uploads[0].sessionId, second = fixture.probe.uploads[1].sessionId
        #expect(first != second, "A closed session can never accept another page")
        try await coachingEventually { fixture.service.currentPage?.sessionId == second }
    }

    @Test("Privacy, disconnection and a different companion are rechecked after image loading")
    func permissionChangeDuringLoadCannotUpload() async throws {
        for change in [CoachingPermissionChange.privateReading, .differentConnection, .disconnected] {
            let fixture = CoachingServiceFixture()
            fixture.probe.holdImages = true
            try fixture.start()
            try await coachingEventually { fixture.probe.imageLoads == 1 }
            switch change {
            case .privateReading: fixture.probe.privateReading = true
            case .differentConnection: fixture.probe.connectionIdentity = "different-companion"
            case .disconnected: fixture.probe.connected = false
            }
            fixture.probe.releaseImages()
            try await Task.sleep(for: .milliseconds(30))
            #expect(fixture.probe.uploads.isEmpty, "A changed permission must prevent pixel transmission")
            #expect(fixture.service.currentPage == nil)
            fixture.close()
        }
    }

    @Test("Credential-bearing source identifiers are rejected before loading or uploading pixels")
    func rejectsSecretIdentifiersBeforeLoading() async throws {
        let fixture = CoachingServiceFixture()
        defer { fixture.close() }
        fixture.probe.capture = fixture.probe.makeCapture(mangaId: "https://books.example/book?apiKey=private")
        try fixture.start()
        fixture.service.refreshVisiblePage()
        await Task.yield()
        #expect(fixture.probe.imageLoads == 0)
        #expect(fixture.probe.uploads.isEmpty)
        #expect(fixture.service.currentPage == nil)
    }

    @Test("Late old-page annotations cannot replace or clear the newer page's pending poll")
    func staleAnnotationReplyCannotPaintNextPage() async throws {
        let fixture = CoachingServiceFixture()
        defer { fixture.close() }
        fixture.probe.holdGets = true
        try fixture.start()
        try await coachingEventually { fixture.probe.uploads.count == 1 }
        fixture.service.refreshVisiblePage()
        try await coachingEventually { fixture.probe.getWaiters.count == 1 }
        fixture.probe.capture = fixture.probe.makeCapture(index: 1)
        fixture.service.refreshVisiblePage()
        try await coachingEventually { fixture.probe.uploads.count == 2 }
        fixture.service.refreshVisiblePage()
        try await coachingEventually { fixture.probe.getWaiters.count == 2 }
        fixture.probe.releaseGet(0, markID: "stale")
        try await Task.sleep(for: .milliseconds(20))
        fixture.service.refreshVisiblePage()
        #expect(fixture.probe.getRequests == 2, "An old completion must not release the new poll's task slot")
        #expect(fixture.service.annotations.isEmpty)
        #expect(fixture.service.currentPage?.page.page == 2)
        fixture.probe.releaseGet(1, markID: "current")
        try await coachingEventually { fixture.service.annotations.first?.id == "current" }
    }

    @Test("Pause and resume retain the same-page drawing while advancing its transport generation")
    func backgroundDraftStaysBoundToTheSamePage() async throws {
        let fixture = CoachingServiceFixture()
        defer { fixture.close() }
        try fixture.start()
        try await coachingEventually { fixture.probe.uploads.count == 1 }
        fixture.service.refreshVisiblePage()
        try await coachingEventually { fixture.service.annotations.first?.id == "coach-note" }
        let before = try #require(fixture.service.currentPage)
        fixture.probe.foreground = false
        fixture.service.refreshVisiblePage()
        let paused = try #require(fixture.service.currentPage)
        #expect(paused.pageId == before.pageId && paused.contentHash == before.contentHash)
        #expect(paused.pageGeneration > before.pageGeneration)
        #expect(fixture.service.annotations.first?.id == "coach-note")
        let displayedPage = try #require(fixture.probe.capture).page
        #expect(!fixture.service.matches(page: displayedPage))
        fixture.probe.foreground = true
        fixture.service.refreshVisiblePage()
        try await coachingEventually { fixture.probe.uploads.count == 2 }
        #expect(fixture.probe.imageLoads == 1, "Resume should reuse the already-consented bitmap")
        #expect(fixture.probe.uploads[1].pageGeneration == paused.pageGeneration)
        #expect(fixture.probe.uploads[1].page.pageId == before.pageId)
        #expect(fixture.service.annotations.first?.id == "coach-note")
        try await coachingEventually { !fixture.probe.pauses.isEmpty }
        #expect(fixture.probe.pauses[0]["pageGeneration"] as? Int == before.pageGeneration)
    }

    @Test("A cancelled pre-pause upload cannot clear the resumed upload's task slot")
    func latePublishCannotReleaseNewAttempt() async throws {
        let fixture = CoachingServiceFixture()
        defer { fixture.close() }
        fixture.probe.holdPosts = true
        try fixture.start()
        try await coachingEventually { fixture.probe.postWaiters.count == 1 }
        fixture.probe.foreground = false
        fixture.service.refreshVisiblePage()
        fixture.probe.foreground = true
        fixture.service.refreshVisiblePage()
        try await coachingEventually { fixture.probe.postWaiters.count == 2 }
        fixture.probe.releasePost(0)
        try await Task.sleep(for: .milliseconds(20))
        fixture.service.refreshVisiblePage()
        #expect(fixture.probe.uploads.count == 2, "The newer upload must retain exclusive ownership of its slot")
        fixture.probe.releasePost(1)
        try await coachingEventually { fixture.service.statusMessage.contains("draw on it") }
        #expect(fixture.service.currentPage?.pageGeneration == fixture.probe.uploads[1].pageGeneration)
    }

    @Test("A lost in-memory page stream republishes automatically while its connection stays enabled")
    func serverRestartAndRevocation() async throws {
        let fixture = CoachingServiceFixture()
        defer { fixture.close() }
        try fixture.start()
        try await coachingEventually { fixture.probe.uploads.count == 1 }
        fixture.probe.inactiveReason = "missing"
        fixture.service.refreshVisiblePage()
        try await coachingEventually { fixture.probe.getRequests == 1 }
        try await Task.sleep(for: .milliseconds(15))
        fixture.probe.now = fixture.probe.now.addingTimeInterval(2)
        fixture.service.refreshVisiblePage()
        try await coachingEventually { fixture.probe.uploads.count == 2 }
        #expect(fixture.probe.imageLoads == 1)
        #expect(fixture.service.isActive)
        fixture.probe.inactiveReason = "revoked"
        fixture.service.refreshVisiblePage()
        try await coachingEventually { !fixture.service.isActive }
        #expect(fixture.service.currentPage == nil && fixture.service.annotations.isEmpty)
        fixture.probe.inactiveReason = nil
        fixture.service.refreshVisiblePage()
        try await coachingEventually { fixture.probe.uploads.count == 3 }
        #expect(fixture.service.isActive)
    }

    @Test("Only the owning reader can stop sharing; failed revocation is best effort without retry loops")
    func ownerAndBestEffortRevoke() async throws {
        let fixture = CoachingServiceFixture()
        defer { fixture.close() }
        try fixture.start()
        try await coachingEventually { fixture.probe.uploads.count == 1 }
        fixture.service.stop(owner: NSObject())
        #expect(fixture.service.isActive)
        #expect(fixture.probe.revokes == 0)
        fixture.probe.failRevokes = true
        fixture.service.stop(owner: fixture.owner)
        #expect(!fixture.service.isActive)
        #expect(fixture.service.currentPage == nil && fixture.service.annotations.isEmpty)
        try await coachingEventually { fixture.probe.revokes == 1 }
        fixture.service.refreshVisiblePage()
        fixture.service.stop(owner: fixture.owner)
        try await Task.sleep(for: .milliseconds(20))
        #expect(fixture.probe.revokes == 1)
        #expect(fixture.probe.uploads.count == 1)
    }

    @Test("Connected page access remains available after the former ten-minute limit")
    func connectionAccessHasNoTimer() async throws {
        let fixture = CoachingServiceFixture()
        defer { fixture.close() }
        try fixture.start()
        try await coachingEventually { fixture.probe.uploads.count == 1 }
        #expect(fixture.probe.uploads[0].accessMode == "connection")
        #expect(fixture.probe.uploads[0].expiresAt == nil)
        fixture.probe.now = fixture.probe.now.addingTimeInterval(30 * 24 * 60 * 60)
        fixture.service.refreshVisiblePage()
        try await coachingEventually { fixture.service.annotations.first?.id == "coach-note" }
        #expect(fixture.service.isActive)
        #expect(fixture.probe.uploads.count == 1)
    }

    @Test("A reader waiting for pairing begins sharing automatically when the connection arrives")
    func connectingBeginsAccessWithoutStartAction() async throws {
        let fixture = CoachingServiceFixture()
        defer { fixture.close() }
        fixture.probe.connected = false
        fixture.service.follow(owner: fixture.owner) { [probe = fixture.probe] in probe.capture }
        #expect(!fixture.service.isActive)
        #expect(fixture.probe.uploads.isEmpty)
        fixture.probe.connected = true
        fixture.service.refreshVisiblePage()
        try await coachingEventually { fixture.probe.uploads.count == 1 }
        #expect(fixture.service.isActive)
    }

    @Test("Closing the book retains last-page access; disconnecting revokes it")
    func closingKeepsLatestPageUntilDisconnection() async throws {
        let fixture = CoachingServiceFixture()
        defer { fixture.close() }
        try fixture.start()
        try await coachingEventually { fixture.service.statusMessage.contains("draw on it") }
        let page = try #require(fixture.service.currentPage)
        fixture.service.detachReader(owner: fixture.owner)
        #expect(fixture.service.isActive)
        #expect(fixture.service.currentPage?.pageId == page.pageId)
        #expect(!fixture.service.matches(page: fixture.probe.capture!.page))
        try await coachingEventually { fixture.probe.pauses.count == 1 }
        #expect(fixture.probe.revokes == 0)
        fixture.probe.now = fixture.probe.now.addingTimeInterval(3600)
        fixture.service.refreshVisiblePage()
        #expect(fixture.probe.uploads.count == 1)
        fixture.probe.connected = false
        fixture.service.refreshVisiblePage()
        #expect(!fixture.service.isActive)
        #expect(fixture.service.currentPage == nil)
        try await coachingEventually { fixture.probe.revokes == 1 }
    }

    @Test("Starting coaching needs both a connected identity and permission to share")
    func startRequiresPermission() throws {
        let fixture = CoachingServiceFixture()
        defer { fixture.close() }
        fixture.probe.connected = false
        #expect(throws: HonbakoPageCoachingService.CoachingError.self) { try fixture.start() }
        fixture.probe.connected = true
        fixture.probe.connectionIdentity = nil
        #expect(throws: HonbakoPageCoachingService.CoachingError.self) { try fixture.start() }
        fixture.probe.connectionIdentity = "fixture-companion"
        fixture.probe.privateReading = true
        #expect(throws: HonbakoPageCoachingService.CoachingError.self) { try fixture.start() }
        #expect(!fixture.service.isActive && fixture.probe.imageLoads == 0 && fixture.probe.uploads.isEmpty)
    }
}

private enum CoachingPermissionChange { case privateReading, differentConnection, disconnected }
private struct CoachingFixtureError: Error {}

@MainActor
private func coachingEventually(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(3)
    while !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("The isolated coaching service did not reach its expected state")
            throw CoachingFixtureError()
        }
        try await Task.sleep(for: .milliseconds(5))
    }
}

@MainActor
private final class CoachingServiceFixture {
    let owner = NSObject()
    let probe = CoachingWireProbe()
    let service: HonbakoPageCoachingService

    init(waitsForImagePolicy: Bool = false) {
        let probe = probe
        service = HonbakoPageCoachingService(transport: { path, method, body in
            try await probe.request(path, method, body)
        }, connected: { probe.connected }, foreground: { probe.foreground },
        privateReading: { probe.privateReading }, now: { probe.now },
        connectionIdentity: { probe.connectionIdentity }, loadImage: { capture in await probe.load(capture) },
        limitedUntil: { probe.limitedUntil }, waitsForImagePolicy: waitsForImagePolicy)
        probe.capture = probe.makeCapture()
    }

    func start() throws { try service.start(owner: owner) { [probe] in probe.capture } }
    func close() { service.stop(); probe.releaseAll() }
}

@MainActor
private final class CoachingWireProbe {
    typealias Models = HonbakoPageCoachingModels
    var connected = true
    var foreground = true
    var privateReading = false
    var connectionIdentity: String? = "fixture-companion"
    var limitedUntil: Date?
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    var capture: HonbakoPageCoachingCapture?
    var holdImages = false
    var holdPosts = false
    var holdGets = false
    var failRevokes = false
    var closeNextPost = false
    var inactiveReason: String?
    var imageLoads = 0
    var uploads: [Models.Publish] = []
    var getRequests = 0
    var revokes = 0
    var pauses: [[String: Any]] = []
    var imageWaiters: [CheckedContinuation<UIImage?, Never>] = []
    var postWaiters: [Int: (Models.Publish, CheckedContinuation<Data, Never>)] = [:]
    var getWaiters: [Int: (Models.Publish, CheckedContinuation<Data, Never>)] = [:]

    func makeCapture(index: Int = 0, mangaId: String = "fixture-book") -> HonbakoPageCoachingCapture {
        let page = Page(sourceId: "fixture-source", chapterId: "fixture-chapter", index: index)
        return .init(page: page, source: nil, sourceId: page.sourceId, mangaId: mangaId, title: "Original fixture",
            chapterId: page.chapterId, chapterTitle: "Chapter 1", chapterNumber: 1,
            canonicalPage: index + 1, totalPages: 10, lastVisiblePage: index + 1)
    }

    func load(_ capture: HonbakoPageCoachingCapture) async -> UIImage? {
        imageLoads += 1
        if holdImages { return await withCheckedContinuation { imageWaiters.append($0) } }
        return image()
    }

    func request(_ path: String, _ method: String, _ body: Data?) async throws -> Data {
        if path.hasSuffix("/revoke") {
            revokes += 1
            if failRevokes { throw CoachingFixtureError() }
            return try JSONSerialization.data(withJSONObject: ["ok": true])
        }
        if path.hasSuffix("/pause") {
            if let body, let value = try JSONSerialization.jsonObject(with: body) as? [String: Any] { pauses.append(value) }
            return try JSONSerialization.data(withJSONObject: ["ok": true])
        }
        if method == "POST", let body {
            let payload = try JSONDecoder().decode(Models.Publish.self, from: body)
            let index = uploads.count
            uploads.append(payload)
            if closeNextPost {
                closeNextPost = false
                throw HonbakoPageCoachingService.CoachingError.sessionClosed
            }
            if holdPosts { return await withCheckedContinuation { postWaiters[index] = (payload, $0) } }
            return acknowledgement(payload)
        }
        guard let payload = uploads.last else { throw CoachingFixtureError() }
        let index = getRequests
        getRequests += 1
        if holdGets { return await withCheckedContinuation { getWaiters[index] = (payload, $0) } }
        return state(payload, markID: "coach-note")
    }

    func releaseImages() {
        let waiting = imageWaiters
        imageWaiters.removeAll()
        for item in waiting { item.resume(returning: image()) }
    }

    func releasePost(_ index: Int) {
        if let item = postWaiters.removeValue(forKey: index) { item.1.resume(returning: acknowledgement(item.0)) }
    }

    func releaseGet(_ index: Int, markID: String) {
        if let item = getWaiters.removeValue(forKey: index) { item.1.resume(returning: state(item.0, markID: markID)) }
    }

    func releaseAll() {
        releaseImages()
        for index in Array(postWaiters.keys) { releasePost(index) }
        for index in Array(getWaiters.keys) { releaseGet(index, markID: "discarded") }
    }

    private func acknowledgement(_ payload: Models.Publish) -> Data {
        try! JSONSerialization.data(withJSONObject: ["ok": true, "sessionId": payload.sessionId,
            "pageId": payload.page.pageId, "expiresAt": NSNull(), "accessMode": "connection", "annotationRevision": 0])
    }

    private func state(_ payload: Models.Publish, markID: String) -> Data {
        var value: [String: Any] = ["active": inactiveReason == nil, "sessionId": payload.sessionId,
            "pageId": payload.page.pageId, "contentHash": payload.page.contentHash,
            "pageGeneration": payload.pageGeneration, "expiresAt": NSNull(), "accessMode": "connection", "annotationRevision": 1,
            "annotations": [["id": markID, "type": "box", "rect": ["x": 0.1, "y": 0.1, "width": 0.2, "height": 0.2]]]]
        if let inactiveReason { value["reason"] = inactiveReason }
        return try! JSONSerialization.data(withJSONObject: value)
    }

    private func image() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 64, height: 96), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 96))
        }
    }
}
