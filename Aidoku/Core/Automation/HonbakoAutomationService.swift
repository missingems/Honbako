#if SUMI
import AidokuRunner
import Combine
import Foundation
import UIKit

/// An explicit, foreground-only bridge to the owner's paired Mac companion.
@MainActor
final class HonbakoAutomationService: ObservableObject {
    typealias Models = HonbakoAutomationModels
    static let shared = HonbakoAutomationService()
    @Published private(set) var isEnabled = false
    @Published private(set) var isConnecting = false
    @Published private(set) var isDisconnecting = false
    @Published private(set) var isMovingConnection = false
    @Published private(set) var sharesReadingPosition = false
    @Published private(set) var status = "Not connected"
    @Published private(set) var errorMessage: String?
    @Published private(set) var pendingApprovals: [Models.Approval] = []
    @Published private(set) var approvingJobID: String?
    @Published private(set) var lastReading: Models.Reading?
    @Published private(set) var lastSync: Date?
    var endpoint: String { connection?.endpoint.absoluteString ?? "" }

    private let defaults = UserDefaults.standard
    private let sessionDelegate = HonbakoAutomationSessionDelegate()
    private var connection: Models.Connection?
    private var session: URLSession?
    private var pollTask: Task<Void, Never>?
    private var pollIdentity = UUID()
    private var lastSnapshotMilliseconds: Int64 = 0
    private var approvalTask: Task<Void, Never>?
    private var persistenceTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var generation = UUID()
    private var readerVisible = false
    private var stateDirty = true
    private var libraryDirty = true
    private var stateRevision: UInt64 = 0
    private var libraryRevision: UInt64 = 0
    private var cachedLibrary: [Models.LibraryItem] = []
    private var cachedSources: [Models.SourceItem] = []
    private var libraryTruncated = false
    private var sourcesTruncated = false
    private var lastStateSent = Date.distantPast
    private var libraryStore: SumiLibraryStore?
    private var preparedBooks: [String: [SumiBook]] = [:]
    private var outbox: [String: Models.JobUpdate] = [:]
    private var receipts: [String: Models.ImportReceipt] = [:]
    private static let enabledKey = "Honbako.Automation.Enabled"
    private static let sharingKey = "Honbako.Automation.ShareReading"
    private static let readingKey = "Honbako.Automation.LastReading"
    private static let outboxKey = "Honbako.Automation.Outbox"
    private static let receiptsKey = "Honbako.Automation.Receipts"
    private static let snapshotTimeKey = "Honbako.Automation.LastSnapshotMilliseconds"

    private var fixtureBlocked: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains(where: { $0.hasPrefix("--sumi-") })
            && !arguments.contains("--honbako-automation-check")
        #else
        return false
        #endif
    }
    private var canPoll: Bool {
        isEnabled && connection != nil && !isMovingConnection && !fixtureBlocked && UIApplication.shared.applicationState == .active
    }

    private init() {
        if let saved = HonbakoAutomationCredentials.load(),
           HonbakoAutomationPolicy.endpoint(saved.endpoint.absoluteString) != nil,
           HonbakoAutomationPolicy.validIdentifier(saved.deviceId),
           HonbakoAutomationPolicy.validDeviceToken(saved.deviceToken) {
            connection = saved
        }
        isEnabled = connection != nil && defaults.bool(forKey: Self.enabledKey)
        sharesReadingPosition = defaults.bool(forKey: Self.sharingKey)
        lastSnapshotMilliseconds = (defaults.object(forKey: Self.snapshotTimeKey) as? NSNumber)?.int64Value ?? 0
        lastReading = Self.decode(Models.Reading.self, key: Self.readingKey)
        lastReading?.active = false
        outbox = Self.decode([String: Models.JobUpdate].self, key: Self.outboxKey) ?? [:]
        receipts = Self.decode([String: Models.ImportReceipt].self, key: Self.receiptsKey) ?? [:]
        observe()
        if isEnabled { status = fixtureBlocked ? "Paused in previews" : "Connecting to your companion…" }
        resume()
    }
    deinit {
        pollTask?.cancel(); approvalTask?.cancel(); persistenceTask?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
        session?.invalidateAndCancel()
    }

    func connect(endpoint value: String, code: String, name: String = "Honbako on iPhone") async {
        guard !isConnecting, !isDisconnecting, !isMovingConnection else { return }
        guard !fixtureBlocked, UIApplication.shared.applicationState == .active else {
            errorMessage = "Open Honbako to connect to your companion."
            return
        }
        guard let endpoint = HonbakoAutomationPolicy.endpoint(value),
              HonbakoAutomationPolicy.validIdentifier(code.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = "Enter your companion companion address and its one-time pairing code."
            return
        }
        pause()
        isConnecting = true; errorMessage = nil
        let identity = generation
        defer { isConnecting = false }
        do {
            let body = Models.PairRequest(code: code.trimmingCharacters(in: .whitespacesAndNewlines), name: String(name.prefix(80)))
            let data = try await request(endpoint: endpoint, path: "api/pair", method: "POST", body: JSONEncoder().encode(body))
            let paired = try JSONDecoder().decode(Models.PairResponse.self, from: data)
            guard identity == generation, !Task.isCancelled,
                  HonbakoAutomationPolicy.validIdentifier(paired.deviceId),
                  HonbakoAutomationPolicy.validDeviceToken(paired.deviceToken) else { throw BridgeError.invalidResponse }
            let connection = Models.Connection(endpoint: endpoint, deviceId: paired.deviceId, deviceToken: paired.deviceToken)
            try HonbakoAutomationCredentials.save(connection)
            self.connection = connection
            outbox = [:]; receipts = [:]; persistQueues()
            isEnabled = true; defaults.set(true, forKey: Self.enabledKey)
            sharesReadingPosition = true; defaults.set(true, forKey: Self.sharingKey)
            invalidateLibrary()
            persistReadingSoon()
            status = "Connected to your companion"
        } catch {
            errorMessage = "Couldn’t pair with your companion. Check the address, code, and Wi-Fi connection."
            status = isEnabled ? "Connection unavailable" : "Not connected"
        }
        if isEnabled { resume() }
    }

    /// Move only the transport address. The device identity and all durable
    /// request/approval state continue to belong to this same pairing.
    @discardableResult
    func moveConnection(to value: String) async -> Bool {
        guard !isMovingConnection, !isConnecting, !isDisconnecting else { return false }
        guard isEnabled, let previous = connection else {
            errorMessage = "Connect to your companion before moving this connection."
            return false
        }
        guard !fixtureBlocked, UIApplication.shared.applicationState == .active else {
            errorMessage = "Open Honbako to move this connection."
            return false
        }
        guard approvingJobID == nil else {
            errorMessage = "Wait for the current book addition to finish before moving the connection."
            return false
        }
        guard let endpoint = HonbakoAutomationPolicy.endpoint(value), endpoint.scheme == "https" else {
            errorMessage = "Enter an HTTPS companion address without a username, password, query, or fragment."
            return false
        }
        if endpoint == previous.endpoint { errorMessage = nil; return true }

        pause()
        isMovingConnection = true
        errorMessage = nil
        status = "Checking the new companion…"
        let identity = generation
        let pendingJobs = pendingApprovals.map(\.job)
        defer {
            isMovingConnection = false
            if isEnabled, !isConnecting, !isDisconnecting { resume() }
        }
        do {
            let moved = try await Self.prepareEndpointMove(to: endpoint.absoluteString, from: previous,
                pendingJobs: pendingJobs) { [self] candidate, token in
                    try await request(endpoint: candidate, path: "api/device/jobs", token: token)
                }
            try Task.checkCancellation()
            guard identity == generation, UIApplication.shared.applicationState == .active,
                  isEnabled, connection?.deviceId == previous.deviceId,
                  connection?.endpoint == previous.endpoint else { throw CancellationError() }
            // No await separates the persistent credential update from the
            // in-memory cutover. A failed save leaves the original pairing intact.
            try HonbakoAutomationCredentials.save(moved)
            connection = moved
            lastSync = nil
            lastStateSent = .distantPast
            invalidateLibrary()
            status = "Connected to your companion"
            return true
        } catch is CancellationError {
            if identity == generation { status = "Connection unchanged" }
        } catch {
            if identity == generation {
                errorMessage = Self.endpointMoveFailureMessage(for: error)
                status = "Connection unchanged"
            }
        }
        return false
    }

    /// The probe authenticates without claiming, processing, or approving jobs.
    /// It is kept separate from persistence so failed/cancelled validation cannot
    /// change a saved endpoint, receipt, or pending addition.
    static func prepareEndpointMove(to value: String, from previous: Models.Connection,
                                    pendingJobs: [Models.Job] = [],
                                    probe: (URL, String) async throws -> Data) async throws -> Models.Connection {
        try Task.checkCancellation()
        guard let endpoint = HonbakoAutomationPolicy.endpoint(value), endpoint.scheme == "https",
              HonbakoAutomationPolicy.validIdentifier(previous.deviceId),
              HonbakoAutomationPolicy.validDeviceToken(previous.deviceToken) else { throw BridgeError.invalidResponse }
        let data = try await probe(endpoint, previous.deviceToken)
        try Task.checkCancellation()
        guard data.count <= 1_048_576 else { throw BridgeError.invalidResponse }
        let jobs = try JSONDecoder().decode(Models.Jobs.self, from: data).jobs
        guard jobs.count <= 100, Set(jobs.map(\.id)).count == jobs.count else { throw BridgeError.invalidResponse }
        for job in jobs { try HonbakoAutomationPolicy.validate(job) }
        let incoming = Dictionary(uniqueKeysWithValues: jobs.map { ($0.id, $0) })
        // A migrated server must still hold requests already shown for approval.
        // Their queue status may advance, but their identities and items may not.
        guard pendingJobs.allSatisfy({ old in
            incoming[old.id].map { $0.kind == old.kind && $0.payload == old.payload } == true
        }) else { throw BridgeError.invalidResponse }
        return Models.Connection(endpoint: endpoint, deviceId: previous.deviceId, deviceToken: previous.deviceToken)
    }

    func disconnect() async {
        guard !isDisconnecting else { return }
        HonbakoPageCoachingService.shared.stop()
        isDisconnecting = true
        pause()
        var cleared = false
        if let connection, UIApplication.shared.applicationState == .active, !fixtureBlocked {
            cleared = (try? await request(endpoint: connection.endpoint, path: "api/device/disconnect", method: "POST",
                body: Data("{}".utf8), token: connection.deviceToken, timeout: 3)) != nil
        }
        isEnabled = false; defaults.set(false, forKey: Self.enabledKey)
        connection = nil; HonbakoAutomationCredentials.clear()
        pendingApprovals = []; preparedBooks = [:]; outbox = [:]; receipts = [:]
        cachedLibrary = []; cachedSources = []; libraryStore = nil; persistQueues()
        status = "Not connected"
        errorMessage = cleared ? nil : "Disconnected on this device. Your companion was unreachable and may retain its last shared page and library snapshot until you clear them there."
        isDisconnecting = false
        session?.invalidateAndCancel(); session = nil
    }

    func setSharingReading(_ enabled: Bool) {
        guard sharesReadingPosition != enabled else { return }
        sharesReadingPosition = enabled
        defaults.set(enabled, forKey: Self.sharingKey)
        HonbakoPageCoachingService.shared.refreshVisiblePage()
        invalidateState()
        if enabled { persistReadingSoon() }
        else { persistenceTask?.cancel(); persistenceTask = nil }
        if canPoll {
            status = "Updating sharing…"
            // Wake the foreground loop now. A new run identity keeps a late
            // cancelled loop from clearing the replacement task's ownership.
            pollIdentity = UUID()
            pollTask?.cancel(); pollTask = nil
            resume()
        }
    }

    func updateReading(sourceId: String, mangaId: String, title: String, chapterId: String, chapterTitle: String,
                       chapterNumber: Float? = nil, volumeNumber: Float? = nil, page: Int,
                       totalPages: Int? = nil, lastVisiblePage: Int? = nil, active: Bool = true) {
        guard !fixtureBlocked,
              var reading = HonbakoAutomationPolicy.reading(sourceId: sourceId, mangaId: mangaId, title: title,
                chapterId: chapterId, chapterTitle: chapterTitle, chapterNumber: chapterNumber, volumeNumber: volumeNumber,
                page: page, totalPages: totalPages, lastVisiblePage: lastVisiblePage,
                updatedAt: Date.now.ISO8601Format(), active: active) else { return }
        readerVisible = active
        reading.active = active && UIApplication.shared.applicationState == .active
        lastReading = reading
        if isEnabled && sharesReadingPosition { invalidateState(); persistReadingSoon() }
    }

    func markReadingInactive() {
        readerVisible = false
        guard lastReading?.active == true else { return }
        lastReading?.active = false; lastReading?.updatedAt = Date.now.ISO8601Format()
        if isEnabled && sharesReadingPosition { invalidateState(); persistReadingSoon() }
    }

    func approve(jobID: String) {
        guard canPoll, approvingJobID == nil,
              let approval = pendingApprovals.first(where: { $0.id == jobID }) else { return }
        approvingJobID = jobID
        let identity = generation
        approvalTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if identity == generation { approvingJobID = nil; approvalTask = nil }
            }
            do {
                guard let connection else { throw CancellationError() }
                // Claim atomically with the Mac before any library mutation.
                try await postStatus(jobID: jobID, update: .init(status: "awaitingApproval", approvalGranted: true), connection: connection)
                try check(identity)
                let items = approval.job.payload.items ?? []
                let key = approval.job.payload.idempotencyKey ?? ""
                if let previous = receipts[key] {
                    guard Set(previous.requested) == Set(items) else { throw BridgeError.invalidResponse }
                    try await finish(jobID, status: "completed", result: previous.result)
                    return
                }
                guard let books = preparedBooks[jobID], books.count == items.count else { throw BridgeError.invalidResponse }
                let store = store()
                var added: [Models.Match] = [], already: [Models.Match] = []
                for book in books {
                    try check(identity)
                    guard await SourceManager.shared.source(for: book.sourceKey) != nil else { throw BridgeError.unavailableSource }
                    let match = match(book.manga)
                    if await isSaved(book.id) { already.append(match); continue }
                    await store.add(book: book)
                    try check(identity)
                    guard await isSaved(book.id) else { throw BridgeError.importFailed }
                    added.append(match)
                }
                let result = Models.AddResult(added: added, alreadyPresent: already)
                receipts[key] = .init(requested: items, result: result)
                if receipts.count > 100, let first = receipts.keys.sorted().first { receipts[first] = nil }
                persistQueues()
                invalidateLibrary()
                try await finish(jobID, status: "completed", result: result)
                status = "Added approved books"
            } catch is CancellationError { /* Leave the durable server request available to resume. */ }
            catch {
                if identity == generation {
                    await fail(jobID, message: "The approved books couldn’t all be added. Some books may already have been added. Check your library before retrying.")
                }
            }
        }
    }

    func sourceName(for id: String) -> String { cachedSources.first { $0.id == id }?.name ?? id }

    func reject(jobID: String) async {
        guard canPoll, approvingJobID == nil else { return }
        removeApproval(jobID)
        outbox[jobID] = .init(status: "rejected"); persistQueues()
        await flushOutbox()
    }

    private func observe() {
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in
                guard let self else { return }
                if readerVisible { lastReading?.active = true }
                invalidateState(); resume()
            } })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification,
            object: nil, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in
                guard let self else { return }
                lastReading?.active = false
                persistReadingSoon()
                pause()
                session?.invalidateAndCancel(); session = nil
            } })
        for name in [Notification.Name.updateLibrary, .updateMangaDetails, .sourceLoaded, .sourceUnloaded, .updateSourceLists] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.invalidateLibrary() }
            })
        }
    }

    private func invalidateState() {
        stateRevision &+= 1
        stateDirty = true
    }
    private func invalidateLibrary() {
        libraryRevision &+= 1
        libraryDirty = true
        invalidateState()
    }

    private func pause() {
        generation = UUID()
        pollTask?.cancel(); pollTask = nil
        approvalTask?.cancel(); approvalTask = nil; approvingJobID = nil
    }
    private func resume() {
        guard canPoll, pollTask == nil else { return }
        let identity = generation
        let runIdentity = UUID()
        pollIdentity = runIdentity
        pollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while canPoll, identity == generation, runIdentity == pollIdentity, !Task.isCancelled {
                do { try await cycle(identity) }
                catch is CancellationError { break }
                catch BridgeError.unauthorized {
                    // A late response from a paused transport cannot revoke a
                    // newer pairing or an endpoint migration already committed.
                    guard !Task.isCancelled, identity == generation, runIdentity == pollIdentity else { break }
                    isEnabled = false; defaults.set(false, forKey: Self.enabledKey)
                    connection = nil; HonbakoAutomationCredentials.clear()
                    status = "Pair with your companion again"
                    break
                } catch {
                    guard !Task.isCancelled, runIdentity == pollIdentity else { break }
                    status = "Companion unavailable — waiting to reconnect"
                }
                do { try await Task.sleep(for: .seconds(3)) } catch { break }
            }
            if identity == generation, runIdentity == pollIdentity { pollTask = nil }
        }
    }
    private func check(_ identity: UUID) throws {
        guard !Task.isCancelled, identity == generation, canPoll else { throw CancellationError() }
    }
    private func store() -> SumiLibraryStore {
        if let libraryStore { return libraryStore }
        let store = SumiLibraryStore(coverPreparer: { _ in })
        libraryStore = store
        return store
    }

    private func cycle(_ identity: UUID) async throws {
        try check(identity)
        guard let connection else { throw CancellationError() }
        await flushOutbox()
        try check(identity)
        if stateDirty || Date.now.timeIntervalSince(lastStateSent) >= 15 {
            let state = try await snapshot(identity)
            let encoded = try JSONEncoder().encode(state)
            let sentRevision = stateRevision
            _ = try await request(endpoint: connection.endpoint, path: "api/device/state", method: "POST",
                body: encoded, token: connection.deviceToken)
            try check(identity)
            stateDirty = stateRevision != sentRevision || libraryDirty
            lastStateSent = .now; lastSync = .now
        }
        let data = try await request(endpoint: connection.endpoint, path: "api/device/jobs", token: connection.deviceToken)
        let jobs = try JSONDecoder().decode(Models.Jobs.self, from: data).jobs
        try check(identity)
        let live = Set(jobs.map(\.id))
        pendingApprovals.removeAll { !live.contains($0.id) && $0.id != approvingJobID }
        preparedBooks = preparedBooks.filter { live.contains($0.key) || $0.key == approvingJobID }
        for job in jobs.prefix(10) {
            try check(identity)
            guard outbox[job.id] == nil, job.id != approvingJobID,
                  !pendingApprovals.contains(where: { $0.id == job.id }) else { continue }
            do {
                try HonbakoAutomationPolicy.validate(job)
                if job.kind == "catalog.search" { try await search(job, identity: identity) }
                else { try await prepareApproval(job, identity: identity) }
            } catch is CancellationError { throw CancellationError() }
            catch { await fail(job.id, message: "This request is unavailable or has invalid items. No books were added.") }
        }
        status = pendingApprovals.isEmpty ? "Connected to your companion" : "Books are waiting for your approval"
    }

    private func snapshot(_ identity: UUID) async throws -> Models.State {
        if libraryDirty {
            let refreshedRevision = libraryRevision
            let store = store()
            guard await store.refreshForReturn() else { throw BridgeError.invalidResponse }
            try check(identity)
            let safe = store.library.filter { HonbakoAutomationPolicy.validItem(.init(sourceId: $0.sourceKey, mangaId: $0.manga.key)) }
            cachedLibrary = safe.prefix(2000).map {
                .init(sourceId: $0.sourceKey, mangaId: $0.manga.key, title: String($0.title.prefix(500)), author: $0.author.map { String($0.prefix(500)) },
                    lastReadPage: $0.lastReadPage.flatMap { $0 >= 1 ? $0 : nil })
            }
            let sources = await SourceManager.shared.getLoadedSources(sorted: true)
            try check(identity)
            cachedSources = sources.filter { HonbakoAutomationPolicy.exportableIdentifier($0.id) }.prefix(100).map {
                .init(id: $0.id, name: String($0.name.prefix(256)), supportsSearch: true)
            }
            libraryTruncated = safe.count != store.library.count || safe.count > cachedLibrary.count
            sourcesTruncated = sources.count > cachedSources.count
            libraryDirty = libraryRevision != refreshedRevision
        }
        let exportedLibrary = sharesReadingPosition ? cachedLibrary : cachedLibrary.map { book in
            var redacted = book
            redacted.lastReadPage = nil
            return redacted
        }
        var state = Models.State(generatedAt: nextSnapshotTimestamp(), library: exportedLibrary, sources: cachedSources,
            reading: sharesReadingPosition ? lastReading : nil, libraryTruncated: libraryTruncated, sourcesTruncated: sourcesTruncated)
        // Keep a large collection below the companion's one-MiB request limit.
        while try JSONEncoder().encode(state).count > 900_000, !state.library.isEmpty {
            state = Models.State(generatedAt: state.generatedAt, library: Array(state.library.dropLast(100)),
                sources: state.sources, reading: state.reading, libraryTruncated: true, sourcesTruncated: state.sourcesTruncated)
        }
        return state
    }

    private func nextSnapshotTimestamp() -> String {
        let current = Int64((Date.now.timeIntervalSince1970 * 1000).rounded(.down))
        lastSnapshotMilliseconds = max(current, lastSnapshotMilliseconds + 1)
        defaults.set(lastSnapshotMilliseconds, forKey: Self.snapshotTimeKey)
        return Date(timeIntervalSince1970: Double(lastSnapshotMilliseconds) / 1000)
            .ISO8601Format(.init(includingFractionalSeconds: true))
    }

    private func search(_ job: Models.Job, identity: UUID) async throws {
        let all = await SourceManager.shared.getLoadedSources(sorted: true)
        let requested = job.payload.sourceIds
        let sources = requested.map { ids in all.filter { ids.contains($0.id) } } ?? Array(all.prefix(20))
        var matches: [Models.Match] = [], errors: [String] = []
        if let requested, Set(requested).subtracting(all.map(\.id)).isEmpty == false { errors.append("Some requested connections are unavailable.") }
        let limit = job.payload.limit ?? 20
        for source in sources {
            try check(identity)
            do {
                let result = try await source.getSearchMangaList(query: job.payload.query, page: 1, filters: [])
                try check(identity)
                for manga in result.entries where matches.count < limit {
                    guard manga.sourceKey == source.id, HonbakoAutomationPolicy.validItem(.init(sourceId: source.id, mangaId: manga.key)),
                          !matches.contains(where: { $0.sourceId == source.id && $0.mangaId == manga.key }) else { continue }
                    matches.append(match(manga))
                }
            } catch is CancellationError { throw CancellationError() }
            catch { errors.append("A selected connection couldn’t complete its search.") }
            if matches.count >= limit { break }
        }
        try await finish(job.id, status: "completed", result: Models.SearchResult(matches: matches, errors: errors.isEmpty ? nil : Array(errors.prefix(20))))
    }

    private func prepareApproval(_ job: Models.Job, identity: UUID) async throws {
        guard let connection, let items = job.payload.items else { throw BridgeError.invalidResponse }
        try await postStatus(jobID: job.id, update: .init(status: "awaitingApproval"), connection: connection)
        var books: [SumiBook] = []
        for item in items {
            try check(identity)
            guard let source = await SourceManager.shared.source(for: item.sourceId) else { throw BridgeError.unavailableSource }
            let requested = AidokuRunner.Manga(sourceKey: item.sourceId, key: item.mangaId, title: "")
            let detailed = try await source.getMangaUpdate(manga: requested, needsDetails: true, needsChapters: true)
            try check(identity)
            guard detailed.sourceKey == item.sourceId, detailed.key == item.mangaId else { throw BridgeError.invalidResponse }
            books.append(SumiBook(manga: detailed))
        }
        preparedBooks[job.id] = books
        pendingApprovals.append(.init(job: job, items: books.map { match($0.manga) }))
    }
    private func match(_ manga: AidokuRunner.Manga) -> Models.Match {
        .init(sourceId: manga.sourceKey, mangaId: manga.key, title: String(manga.title.prefix(500)),
            author: manga.authors.map { String($0.joined(separator: ", ").prefix(500)) })
    }
    private func isSaved(_ identifier: MangaIdentifier) async -> Bool {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.hasLibraryManga(mangaId: identifier, context: context)
        }
    }
    private func removeApproval(_ id: String) {
        pendingApprovals.removeAll { $0.id == id }; preparedBooks[id] = nil
    }
    private func finish<T: Encodable>(_ id: String, status: String, result: T) async throws {
        outbox[id] = .init(status: status, result: try .encoding(result))
        removeApproval(id); persistQueues()
        await flushOutbox()
    }
    private func fail(_ id: String, message: String) async {
        guard HonbakoAutomationPolicy.validIdentifier(id), canPoll else { return }
        outbox[id] = .init(status: "failed", error: message)
        removeApproval(id); persistQueues()
        await flushOutbox()
    }
    private func flushOutbox() async {
        guard canPoll, let connection else { return }
        let identity = generation
        for (id, update) in outbox {
            do {
                try await postStatus(jobID: id, update: update, connection: connection)
                guard !Task.isCancelled, identity == generation, canPoll else { break }
                outbox[id] = nil; persistQueues()
            } catch BridgeError.conflict {
                guard !Task.isCancelled, identity == generation, canPoll else { break }
                outbox[id] = nil; persistQueues()
            } catch { break }
        }
    }
    private func postStatus(jobID: String, update: Models.JobUpdate, connection: Models.Connection) async throws {
        guard HonbakoAutomationPolicy.validIdentifier(jobID) else { throw BridgeError.invalidResponse }
        _ = try await request(endpoint: connection.endpoint, path: "api/device/jobs/\(jobID)/status", method: "POST",
            body: JSONEncoder().encode(update), token: connection.deviceToken)
    }
    private func request(endpoint: URL, path: String, method: String = "GET", body: Data? = nil,
                         token: String? = nil, timeout: TimeInterval = 10) async throws -> Data {
        guard !fixtureBlocked, UIApplication.shared.applicationState == .active,
              isEnabled || isConnecting || isDisconnecting else { throw CancellationError() }
        if session == nil {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false; configuration.urlCredentialStorage = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 10; configuration.timeoutIntervalForResource = 15
            session = URLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: nil)
        }
        guard let session, let checkedEndpoint = HonbakoAutomationPolicy.endpoint(endpoint.absoluteString),
              token.map(HonbakoAutomationPolicy.validDeviceToken) ?? true else { throw BridgeError.invalidResponse }
        var request = URLRequest(url: checkedEndpoint.appendingPathComponent(path))
        request.httpMethod = method; request.httpBody = body; request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, data.count <= 1_048_576 else { throw BridgeError.invalidResponse }
        if response.statusCode == 401 { throw BridgeError.unauthorized }
        if response.statusCode == 409 { throw BridgeError.conflict }
        guard (200...299).contains(response.statusCode) else { throw BridgeError.httpStatus(response.statusCode) }
        return data
    }
    var coachingConnectionIdentity: String? {
        connection.map { "\($0.deviceId)|\($0.endpoint.absoluteString)" }
    }

    /// Page coaching uses the same paired, redirect-rejecting transport.
    /// Its pixels are never persisted with the metadata snapshot or approval outbox.
    func coachingRequest(path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        let allowed = ["api/device/coaching", "api/device/coaching/revoke", "api/device/coaching/pause"]
        guard allowed.contains(path), let current = connection, isEnabled, !isConnecting, !isDisconnecting else {
            throw BridgeError.invalidResponse
        }
        let data = try await request(endpoint: current.endpoint, path: path, method: method, body: body, token: current.deviceToken)
        guard connection?.deviceId == current.deviceId, connection?.deviceToken == current.deviceToken,
              connection?.endpoint == current.endpoint else { throw CancellationError() }
        return data
    }

    private func persistQueues() {
        if let data = try? JSONEncoder().encode(outbox) { defaults.set(data, forKey: Self.outboxKey) }
        if let data = try? JSONEncoder().encode(receipts) { defaults.set(data, forKey: Self.receiptsKey) }
    }
    private func persistReadingSoon() {
        guard isEnabled, sharesReadingPosition else { return }
        persistenceTask?.cancel()
        persistenceTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            guard let self, isEnabled, sharesReadingPosition,
                  let reading = lastReading, let data = try? JSONEncoder().encode(reading) else { return }
            defaults.set(data, forKey: Self.readingKey)
        }
    }
    private static func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
    static func endpointMoveFailureMessage(for error: Error) -> String {
        let reason: String
        switch error {
        case BridgeError.unauthorized:
            reason = String(localized: "The server does not recognize this phone’s existing pairing (HTTP 401). Its saved pairing must be migrated before moving.")
        case BridgeError.httpStatus(let status):
            if status == 404 {
                reason = String(localized: "The phone endpoint was not found (HTTP 404). Enter the server’s base HTTPS address without /mcp.")
            } else {
                reason = String(localized: "The server rejected the connection check (HTTP \(status)).")
            }
        case let network as URLError:
            if network.code == .timedOut {
                reason = String(localized: "The connection check timed out. Keep Honbako open and check that the server is reachable from this phone.")
            } else {
                let code = String(network.code.rawValue)
                reason = String(localized: "The phone could not reach the server (network error \(code)).")
            }
        case is DecodingError:
            reason = String(localized: "The address did not return a valid Honbako phone response. Use the server’s base HTTPS address without /mcp.")
        default:
            reason = String(localized: "The server response did not match this pairing or its pending requests.")
        }
        return reason + " " + String(localized: "Your existing connection is unchanged.")
    }

    private enum BridgeError: Error { case invalidResponse, unauthorized, conflict, unavailableSource, importFailed, httpStatus(Int) }
}
#endif
