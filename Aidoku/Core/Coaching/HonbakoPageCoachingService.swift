#if SUMI
import Combine
import Foundation
import UIKit

/// Page access follows the paired connection. Fresh pixels are captured only
/// from the foreground reader; the last shared page remains available. Pixels stay
/// in memory on the phone; they never enter backups, defaults, or the job outbox.
@MainActor
final class HonbakoPageCoachingService: ObservableObject {
    typealias Models = HonbakoPageCoachingModels
    typealias Transport = @MainActor (String, String, Data?) async throws -> Data
    static let shared: HonbakoPageCoachingService = {
        #if DEBUG
        if HonbakoPageAccessPreview.isEnabled { return HonbakoPageAccessPreview.makeService() }
        #endif
        return HonbakoPageCoachingService()
    }()
    static let updated = Notification.Name("Honbako.PageCoaching.Updated")

    @Published private(set) var isActive = false
    @Published private(set) var currentPage: Models.PageReference?
    @Published private(set) var annotations: [Models.Annotation] = []
    @Published private(set) var statusMessage = ""

    private let transport: Transport
    private let connected: @MainActor () -> Bool
    private let annotationsPermitted: @MainActor () -> Bool
    private let foreground: @MainActor () -> Bool
    private let privateReading: @MainActor () -> Bool
    private let now: @MainActor () -> Date
    private let connectionIdentity: @MainActor () -> String?
    /// While the hosted server is refusing requests, the session tick sends nothing.
    private let limitedUntil: @MainActor () -> Date?
    private var boundConnectionIdentity: String?
    private let loadImage: @MainActor (HonbakoPageCoachingCapture) async -> UIImage?
    private var ownerID: ObjectIdentifier?
    private var sessionID: String?
    private var captureProvider: (@MainActor () -> HonbakoPageCoachingCapture?)?
    private var localPage: Page?
    private var captureChapterID: String?
    private var publishAttempt = UUID()
    private var annotationAttempt = UUID()
    private var pendingPublish: Models.Publish?
    private var published = false
    private var pageGeneration = 0
    private var revision = 0
    private var nextPublishAttempt = Date.distantPast
    private var wasVisible = false
    /// Jobs polls carry a drawing summary; while they arrive, drawings are fetched only when it
    /// changes. Without one (an older companion or server), the reader checks every tick.
    private var lastSummary: Models.Summary?
    private var summaryChanged = false
    private var summarySeenAt: Date?
    /// Whether the server takes page pixels only when an AI asks; nil until the first jobs poll
    /// answers. A reader waits briefly for that answer, so no image goes up before it is known.
    private var serverImagesOnRequest: Bool?
    private let waitsForImagePolicy: Bool
    private var followedAt: Date?
    /// The summary whose image request was last answered, so each request uploads pixels once.
    private var answeredImageRequest: Models.Summary?
    private var driverTask: Task<Void, Never>?
    private var publishTask: Task<Void, Never>?
    private var annotationTask: Task<Void, Never>?

    convenience init() {
        self.init(transport: { path, method, body in
            try await HonbakoAutomationService.shared.coachingRequest(path: path, method: method, body: body)
        }, connected: { HonbakoAutomationService.shared.isEnabled && HonbakoAutomationService.shared.pageAccessAllowed },
        foreground: { UIApplication.shared.applicationState == .active },
        privateReading: { AppSettings.general.incognitoMode.get() }, now: Date.init,
        connectionIdentity: { HonbakoAutomationService.shared.coachingConnectionIdentity },
        annotationsPermitted: { HonbakoAutomationService.shared.annotationsAllowed },
        limitedUntil: { HonbakoAutomationService.shared.limitedUntil }, waitsForImagePolicy: true)
    }

    init(transport: @escaping Transport, connected: @escaping @MainActor () -> Bool,
         foreground: @escaping @MainActor () -> Bool,
         privateReading: @escaping @MainActor () -> Bool, now: @escaping @MainActor () -> Date,
         connectionIdentity: @escaping @MainActor () -> String?,
         loadImage: (@MainActor (HonbakoPageCoachingCapture) async -> UIImage?)? = nil,
         annotationsPermitted: @escaping @MainActor () -> Bool = { true },
         limitedUntil: @escaping @MainActor () -> Date? = { nil },
         waitsForImagePolicy: Bool = false) {
        self.transport = transport
        self.waitsForImagePolicy = waitsForImagePolicy
        self.limitedUntil = limitedUntil
        self.connected = connected
        self.annotationsPermitted = annotationsPermitted
        self.foreground = foreground
        self.privateReading = privateReading
        self.now = now
        self.connectionIdentity = connectionIdentity
        let loader = HonbakoJapanesePageLoader()
        self.loadImage = loadImage ?? { capture in
            await loader.image(for: capture.page, source: capture.source)
        }
    }

    enum CoachingError: LocalizedError {
        case connectionRequired, privateReading, sessionClosed
        var errorDescription: String? {
            switch self {
            case .connectionRequired: "Connect an assistant in Settings → AI Connections first."
            case .privateReading: "Page coaching is unavailable during private reading."
            case .sessionClosed: "This page stream was closed."
            }
        }
    }

    /// Attach a visible reader. Connecting MCP supplies permission; no dialog
    /// or per-book timer is required, including when the connection comes later.
    func follow(owner: AnyObject, capture: @escaping @MainActor () -> HonbakoPageCoachingCapture?) {
        if ownerID != ObjectIdentifier(owner), wasVisible { pauseVisiblePage() }
        ownerID = ObjectIdentifier(owner)
        captureProvider = capture
        followedAt = followedAt ?? now()
        if driverTask == nil {
            driverTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    guard self != nil else { return }
                    self?.refreshVisiblePage()
                    do { try await Task.sleep(for: .milliseconds(750)) } catch { return }
                }
            }
        }
        refreshVisiblePage()
    }

    /// Retained as a checked entry point for isolated callers and tests.
    func start(owner: AnyObject, capture: @escaping @MainActor () -> HonbakoPageCoachingCapture?) throws {
        guard connected(), connectionIdentity() != nil else { throw CoachingError.connectionRequired }
        guard !privateReading() else { throw CoachingError.privateReading }
        stop()
        follow(owner: owner, capture: capture)
    }

    /// Closing a book stops capture, while connection permission and the last
    /// shared page remain available for questions asked outside the reader.
    func detachReader(owner: AnyObject) {
        guard ownerID == ObjectIdentifier(owner) else { return }
        if wasVisible { pauseVisiblePage() }
        ownerID = nil
        captureProvider = nil
    }

    func stop(owner: AnyObject? = nil) {
        if let owner, ownerID != ObjectIdentifier(owner) { return }
        driverTask?.cancel(); driverTask = nil
        clearAccess()
        ownerID = nil
        captureProvider = nil
    }

    private func clearAccess() {
        let revokedSession = boundConnectionIdentity == connectionIdentity() ? sessionID : nil
        publishTask?.cancel(); publishTask = nil
        annotationTask?.cancel(); annotationTask = nil
        isActive = false
        boundConnectionIdentity = nil
        sessionID = nil
        localPage = nil
        captureChapterID = nil
        publishAttempt = UUID(); annotationAttempt = UUID()
        currentPage = nil
        pendingPublish = nil
        annotations = []
        published = false
        revision = 0
        wasVisible = false
        statusMessage = ""
        notify()
        if let revokedSession {
            let transport = transport
            Task { @MainActor in
                _ = try? await transport("api/device/coaching/revoke", "POST",
                    JSONEncoder().encode(Models.Session(sessionId: revokedSession)))
            }
        }
    }

    /// Called after each jobs poll with the server's drawing summary, or nil when it sent none.
    func receive(_ summary: Models.Summary?) {
        guard let summary else { summarySeenAt = nil; serverImagesOnRequest = false; return }
        summarySeenAt = now()
        serverImagesOnRequest = summary.imagesOnRequest == true
        if summary != lastSummary { lastSummary = summary; summaryChanged = true }
    }

    private var summariesArrive: Bool {
        summarySeenAt.map { now().timeIntervalSince($0) < 15 } ?? false
    }

    private var mayShare: Bool {
        isActive && connected() && boundConnectionIdentity == connectionIdentity()
            && foreground() && !privateReading()
    }

    func matches(page: Page) -> Bool {
        isActive && boundConnectionIdentity == connectionIdentity() && foreground() && !privateReading()
            && ownerID != nil && currentPage != nil && localPage == page
    }

    /// Called by the small session driver. A page turn immediately hides the
    /// old marks, even while its replacement bitmap is still loading.
    func refreshVisiblePage() {
        if !annotationsPermitted(), !annotations.isEmpty { annotations = []; notify() }
        guard connected(), let identity = connectionIdentity(), !privateReading() else {
            if isActive { clearAccess() }
            return
        }
        if !isActive || boundConnectionIdentity != identity {
            clearAccess()
            boundConnectionIdentity = identity
            sessionID = UUID().uuidString.lowercased()
            pageGeneration = 0
            isActive = true
            statusMessage = "Waiting for a readable manga page…"
            notify()
        }
        guard foreground(), let capture = captureProvider?() else {
            if wasVisible { pauseVisiblePage() }
            return
        }
        if !wasVisible {
            wasVisible = true
            published = false
            nextPublishAttempt = .distantPast
            notify()
        }
        if let until = limitedUntil(), until > now() {
            if localPage != capture.page, !annotations.isEmpty { annotations = []; notify() }
            return
        }
        if waitsForImagePolicy, serverImagesOnRequest == nil,
           now().timeIntervalSince(followedAt ?? now()) < 12 { return }
        if localPage != capture.page || captureChapterID != capture.chapterId
            || (currentPage == nil && publishTask == nil && now() >= nextPublishAttempt) {
            beginPage(capture)
        } else if !published, publishTask == nil, now() >= nextPublishAttempt, let payload = pendingPublish {
            send(payload)
        }
        if published, publishTask == nil, mayShare, serverImagesOnRequest == true, let payload = pendingPublish,
           let summary = lastSummary, summary.imageRequested == true, summary.sessionId == payload.sessionId,
           summary.pageId == payload.page.pageId, answeredImageRequest != summary {
            answeredImageRequest = summary
            send(payload, withImage: true)
        }
        if published, annotationTask == nil, let reference = currentPage, summaryChanged || !summariesArrive {
            summaryChanged = false
            poll(reference)
        }
    }

    private func beginPage(_ capture: HonbakoPageCoachingCapture) {
        guard mayShare, HonbakoPageCoachingPolicy.validCapture(capture) else {
            annotations = []
            currentPage = nil
            statusMessage = "This page cannot be shared."
            notify()
            return
        }
        publishAttempt = UUID(); annotationAttempt = UUID()
        publishTask?.cancel()
        annotationTask?.cancel(); annotationTask = nil
        pageGeneration += 1
        let generation = pageGeneration
        guard let sessionID else { return }
        let previousPage = pendingPublish?.page
        localPage = capture.page
        captureChapterID = capture.chapterId
        currentPage = nil
        pendingPublish = nil
        published = false
        annotations = []
        revision = 0
        statusMessage = "Sharing the visible page…"
        notify()
        publishTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let image = await self.loadImage(capture)
            guard !Task.isCancelled, self.isActive, self.sessionID == sessionID, self.pageGeneration == generation, self.mayShare, let image, let encoded = HonbakoPageCoachingImageEncoder.encode(image) else {
                if !Task.isCancelled, self.sessionID == sessionID, self.pageGeneration == generation {
                    self.publishTask = nil
                    self.nextPublishAttempt = self.now().addingTimeInterval(3)
                    self.statusMessage = "This page cannot be shared yet."
                }
                return
            }
            let samePage = previousPage.map {
                $0.sourceId == capture.sourceId && $0.mangaId == capture.mangaId && $0.chapterId == capture.chapterId
                    && $0.page == capture.canonicalPage && $0.contentHash == encoded.contentHash
            } == true
            let context = Models.PageContext(pageId: samePage ? (previousPage?.pageId ?? UUID().uuidString.lowercased()) : UUID().uuidString.lowercased(), contentHash: encoded.contentHash,
                sourceId: capture.sourceId, mangaId: capture.mangaId, title: String(capture.title.prefix(500)),
                chapterId: capture.chapterId, chapterTitle: String(capture.chapterTitle.prefix(500)), chapterNumber: capture.chapterNumber,
                page: capture.canonicalPage, totalPages: capture.totalPages, lastVisiblePage: capture.lastVisiblePage,
                capturedAt: HonbakoPageCoachingPolicy.timestamp(self.now()))
            let payload = Models.Publish(sessionId: sessionID, pageGeneration: generation, page: context,
                image: encoded.image, expiresAt: nil, accessMode: "connection")
            self.currentPage = Models.PageReference(sessionId: sessionID, pageGeneration: generation, page: context)
            self.pendingPublish = payload
            self.publishTask = nil
            self.send(payload)
        }
    }

    /// Pixels go up with every page when the server needs them; otherwise only page details do,
    /// and the image follows once, when an AI asks for this page.
    private func send(_ payload: Models.Publish, withImage: Bool = false) {
        guard publishTask == nil, mayShare else { return }
        var context = payload.page
        context.capturedAt = HonbakoPageCoachingPolicy.timestamp(now())
        let payload = Models.Publish(sessionId: payload.sessionId, pageGeneration: payload.pageGeneration,
            page: context, image: payload.image, expiresAt: nil, accessMode: "connection")
        pendingPublish = payload
        var wire = payload
        if serverImagesOnRequest == true, !withImage { wire.image = nil }
        currentPage = Models.PageReference(sessionId: payload.sessionId, pageGeneration: payload.pageGeneration, page: context)
        let attempt = UUID()
        publishAttempt = attempt
        publishTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.publishAttempt == attempt { self.publishTask = nil }
            }
            guard self.mayShare else { return }
            do {
                let bytes = try await self.transport("api/device/coaching", "POST", JSONEncoder().encode(wire))
                try Task.checkCancellation()
                let result = try JSONDecoder().decode(Models.Published.self, from: bytes)
                guard self.isActive, self.sessionID == payload.sessionId, self.pageGeneration == payload.pageGeneration,
                      result.ok, result.sessionId == payload.sessionId, result.pageId == payload.page.pageId,
                      result.accessMode == "connection", result.expiresAt == nil else { return }
                self.published = true
                self.statusMessage = wire.image == nil ? "Your assistant can ask for this page." : "Your assistant can view this page and draw on it."
                self.notify()
            } catch CoachingError.sessionClosed {
                // The server closed this stream (revoked, or replaced after a
                // restart). Retrying the same session can never succeed, so the
                // next tick starts a fresh one.
                guard !Task.isCancelled, self.sessionID == payload.sessionId else { return }
                self.clearAccess()
            } catch {
                if wire.image != nil { self.answeredImageRequest = nil }
                guard !Task.isCancelled, self.sessionID == payload.sessionId,
                      self.pageGeneration == payload.pageGeneration else { return }
                self.published = false
                self.nextPublishAttempt = self.now().addingTimeInterval(3)
                self.statusMessage = "Waiting for the AI connection…"
            }
        }
    }

    private func poll(_ reference: Models.PageReference) {
        guard mayShare else { return }
        let attempt = UUID()
        annotationAttempt = attempt
        annotationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.annotationAttempt == attempt { self.annotationTask = nil }
            }
            guard self.mayShare else { return }
            do {
                let bytes = try await self.transport("api/device/coaching", "GET", nil)
                try Task.checkCancellation()
                guard self.isActive, self.foreground(), self.currentPage == reference else { return }
                let state = try JSONDecoder().decode(Models.State.self, from: bytes)
                if !state.active {
                    if ["expired", "revoked", "restart"].contains(state.reason ?? "")
                        || state.sessionId.map({ $0 != reference.sessionId }) == true {
                        self.clearAccess()
                    } else {
                        self.published = false
                        self.nextPublishAttempt = self.now().addingTimeInterval(1)
                    }
                    return
                }
                if HonbakoPageCoachingPolicy.accepts(state, for: reference, after: self.revision, now: self.now()) {
                    self.annotations = self.annotationsPermitted() ? state.annotations : []
                    self.revision = state.annotationRevision
                    self.notify()
                }
            } catch {
                // A failed poll never applies a partial or stale drawing; the next summary retries it.
                self.lastSummary = nil
            }
        }
    }

    private func pauseVisiblePage() {
        let pausedReference = currentPage
        wasVisible = false
        published = false
        publishAttempt = UUID(); annotationAttempt = UUID()
        publishTask?.cancel(); publishTask = nil
        annotationTask?.cancel(); annotationTask = nil
        // A new transport generation rejects old callbacks and delayed pauses,
        // while retaining drawings for the exact same approved image.
        pageGeneration += 1
        if let payload = pendingPublish {
            pendingPublish = Models.Publish(sessionId: payload.sessionId, pageGeneration: pageGeneration,
                page: payload.page, image: payload.image, expiresAt: nil, accessMode: "connection")
            currentPage = Models.PageReference(sessionId: payload.sessionId, pageGeneration: pageGeneration, page: payload.page)
        }
        statusMessage = "Your assistant can use the last shared page."
        notify()
        if let pausedReference, boundConnectionIdentity == connectionIdentity() {
            let transport = transport
            Task { @MainActor in
                _ = try? await transport("api/device/coaching/pause", "POST",
                    JSONEncoder().encode(Models.Pause(sessionId: pausedReference.sessionId,
                        pageGeneration: pausedReference.pageGeneration, pageId: pausedReference.pageId)))
            }
        }
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.updated, object: self)
    }
}
#endif
