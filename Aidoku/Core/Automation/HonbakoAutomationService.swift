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
    @Published private(set) var remoteSetupAvailable: Bool?
    @Published private(set) var remoteSetupMessage: String?
    @Published private(set) var isDisconnecting = false
    @Published private(set) var isMovingConnection = false
    @Published private(set) var sharesReadingPosition = false
    @Published private(set) var status = "Not connected"
    @Published private(set) var errorMessage: String?
    @Published private(set) var pendingApprovals: [Models.Approval] = []
    @Published private(set) var approvingJobID: String?
    @Published private(set) var lastReading: Models.Reading?
    @Published private(set) var lastSync: Date?
    /// The other devices on this Pro purchase that share the hosted workspace.
    @Published private(set) var devices: [HonbakoAutomationWorkspace.Device] = []
    @Published private(set) var joinedOtherDevices = false
    @Published private(set) var handledNotices: [HonbakoAutomationWorkspace.HandledNotice] = []
    @Published private(set) var isRemovingDevice = false
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
    private var remoteAvailabilityGeneration = 0
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
    private var isRejoining = false
    private var rejoinAttempted = false
    private static let enabledKey = "Honbako.Automation.Enabled"
    private static let sharingKey = "Honbako.Automation.ShareReading"
    private static let readingKey = "Honbako.Automation.LastReading"
    private static let outboxKey = "Honbako.Automation.Outbox"
    private static let receiptsKey = "Honbako.Automation.Receipts"
    private static let snapshotTimeKey = "Honbako.Automation.LastSnapshotMilliseconds"
    private static let workspaceKey = "Honbako.Automation.WorkspaceID"
    private static let permissionsRevisionKey = "Honbako.MCP.PermissionsRevision"
    private static let permissionsPendingKey = "Honbako.MCP.PermissionsPending"
    /// Shown in the Devices list and in "Handled on iPad" on the other devices.
    static var deviceName: String { UIDevice.current.model }

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
        isEnabled && connection != nil && !isMovingConnection && !isRejoining && !fixtureBlocked && UIApplication.shared.applicationState == .active
    }

    private init() {
        if !fixtureBlocked, let saved = HonbakoAutomationCredentials.load(),
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

    func connect(endpoint value: String, code: String, name: String? = nil) async {
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
            let name = name ?? "Honbako on \(Self.deviceName)"
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
            adoptDefaultSharing()
            invalidateLibrary()
            persistReadingSoon()
            status = "Connected to your companion"
        } catch {
            errorMessage = "Couldn’t pair with your companion. Check the address, code, and Wi-Fi connection."
            status = isEnabled ? "Connection unavailable" : "Not connected"
        }
        if isEnabled { resume() }
    }

    @discardableResult
    func checkRemoteAvailability() async -> Bool {
        remoteAvailabilityGeneration += 1
        let check = remoteAvailabilityGeneration
        let unavailable = "Remote hosting isn’t available yet. You can use a local Mac connection below."
        guard !fixtureBlocked else {
            remoteSetupAvailable = false
            remoteSetupMessage = unavailable
            return false
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForResource = 10
        let probe = URLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: nil)
        defer { probe.invalidateAndCancel() }
        do {
            let (data, response) = try await probe.data(from: managedRemoteEndpoint.appendingPathComponent("capabilities"))
            guard check == remoteAvailabilityGeneration, !Task.isCancelled else { return false }
            guard let response = response as? HTTPURLResponse, response.statusCode == 200, data.count <= 4096 else {
                remoteSetupAvailable = false
                remoteSetupMessage = (response as? HTTPURLResponse)?.statusCode == 503
                    ? unavailable : "Couldn’t check remote hosting. Check your internet connection and try again."
                return false
            }
            let available = try JSONDecoder().decode(HonbakoRemoteMCP.Capabilities.self, from: data).available
            remoteSetupAvailable = available
            remoteSetupMessage = available ? nil : unavailable
            return available
        } catch {
            guard check == remoteAvailabilityGeneration, !Task.isCancelled else { return false }
            remoteSetupAvailable = false
            remoteSetupMessage = "Couldn’t check remote hosting. Check your internet connection and try again."
            return false
        }
    }

    var usesManagedRemote: Bool { connection.map { HonbakoRemoteMCP.isManaged($0.endpoint) } ?? false }
    /// The server shares this purchase's workspace across devices, with one set of switches.
    private var usesSharedWorkspace: Bool { usesManagedRemote && defaults.string(forKey: Self.workspaceKey) != nil }

    /// Existing pairings stay on their original production or Sandbox workspace.
    private var managedRemoteEndpoint: URL {
        guard let connection, HonbakoRemoteMCP.isManaged(connection.endpoint) else { return HonbakoRemoteMCP.endpoint }
        return connection.endpoint
    }

    /// Creates a private workspace without asking for an address, pairing code or AI key.
    func enableRemoteServer() async {
        guard !isConnecting, !isDisconnecting, !isMovingConnection else { return }
        guard !isEnabled else { return }
        guard remoteSetupAvailable == true else {
            errorMessage = "Automatic remote setup is not available yet."
            return
        }
        guard !fixtureBlocked, UIApplication.shared.applicationState == .active else { return }
        isConnecting = true; errorMessage = nil
        defer { isConnecting = false }
        guard let proof = await HonbakoProStore.shared.remotePurchaseProof() else {
            errorMessage = "Remote MCP needs an active App Store Pro subscription. Personal-build access does not include hosting."
            return
        }
        do {
            let endpoint = proof.endpoint
            let identity = try HonbakoAutomationCredentials.remoteIdentity(endpoint: endpoint)
            let enrolled = try await enroll(endpoint: endpoint, identity: identity, proof: proof)
            let connected = Models.Connection(endpoint: endpoint, deviceId: enrolled.deviceId, deviceToken: enrolled.deviceToken)
            try HonbakoAutomationCredentials.save(connected)
            connection = connected
            outbox = [:]; receipts = [:]; persistQueues()
            isEnabled = true; defaults.set(true, forKey: Self.enabledKey)
            adoptDefaultSharing()
            // A device joining others takes the account's switches; a first device offers its own.
            defaults.set(enrolled.workspaceId, forKey: Self.workspaceKey)
            defaults.set(0, forKey: Self.permissionsRevisionKey); defaults.set(false, forKey: Self.permissionsPendingKey)
            joinedOtherDevices = enrolled.joinedOtherDevices == true
            invalidateLibrary(); persistReadingSoon()
            status = HonbakoAutomationWorkspace.enrolledStatus(joinedOtherDevices: enrolled.joinedOtherDevices)
            resume()
        } catch BridgeError.httpStatus(402) {
            errorMessage = "Apple could not confirm an active Pro subscription for remote MCP. Restore Purchases and try again."
        } catch BridgeError.httpStatus(503) {
            errorMessage = "Automatic remote setup is not available yet. Your existing library is unchanged."
        } catch BridgeError.refused(_, "purchase_mismatch") {
            errorMessage = "This iPhone’s remote server belongs to a different Pro purchase. Sign in with the Apple Account that bought Pro and tap Restore Purchases, or contact jun@honbako.xyz."
        } catch BridgeError.refused(_, "device_limit") {
            errorMessage = "Your Pro subscription is already using remote MCP on five devices. On one of them, remove a device you no longer use in MCP Server → Devices, then try again."
        } catch BridgeError.refused(_, "rate_limited") {
            errorMessage = "Too many setup attempts. Wait a few minutes, then try again."
        } catch {
            errorMessage = "Couldn’t enable the remote MCP server. Try again when you’re connected to the internet."
        }
    }

    private func enroll(endpoint: URL, identity: HonbakoRemoteMCPIdentity,
                        proof: HonbakoRemotePurchaseProof) async throws -> HonbakoRemoteMCP.Enrolled {
        let body = HonbakoRemoteMCP.Enrollment(installationId: identity.installationId,
            deviceSecret: identity.deviceSecret, name: Self.deviceName, signedTransaction: proof.signedTransaction)
        let data = try await request(endpoint: endpoint, path: "enroll", method: "POST", body: JSONEncoder().encode(body), timeout: 30)
        let enrolled = try JSONDecoder().decode(HonbakoRemoteMCP.Enrolled.self, from: data)
        guard enrolled.endpoint == endpoint, enrolled.deviceId == identity.installationId,
              HonbakoAutomationPolicy.validDeviceToken(enrolled.deviceToken),
              enrolled.workspaceId.map(HonbakoAutomationPolicy.validIdentifier) ?? true else { throw BridgeError.invalidResponse }
        return enrolled
    }

    /// Pairings made before shared workspaces enroll once more, so this device joins the
    /// other devices on its Pro purchase. Polling stops meanwhile: joining closes this
    /// device's old workspace, and a late poll with its old token must not look like a removal.
    private func rejoinSharedWorkspaceIfNeeded() -> Bool {
        guard HonbakoAutomationWorkspace.needsRejoin(managed: usesManagedRemote, enabled: isEnabled,
                workspaceId: defaults.string(forKey: Self.workspaceKey), attempted: rejoinAttempted),
              canPoll, let previous = connection else { return false }
        rejoinAttempted = true
        pause()
        isRejoining = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { isRejoining = false; resume() }
            guard let proof = await HonbakoProStore.shared.remotePurchaseProof(), proof.endpoint == previous.endpoint,
                  let identity = try? HonbakoAutomationCredentials.remoteIdentity(endpoint: previous.endpoint),
                  identity.installationId == previous.deviceId,
                  let enrolled = try? await enroll(endpoint: previous.endpoint, identity: identity, proof: proof),
                  let workspaceId = enrolled.workspaceId,
                  isEnabled, connection?.deviceId == previous.deviceId, connection?.endpoint == previous.endpoint else { return }
            // Keep the existing pairing if the new one can't be saved; this retries next launch.
            let joined = Models.Connection(endpoint: previous.endpoint, deviceId: enrolled.deviceId, deviceToken: enrolled.deviceToken)
            guard (try? HonbakoAutomationCredentials.save(joined)) != nil else { return }
            if joined.deviceToken != previous.deviceToken {
                // Requests queued in the old workspace closed with it.
                connection = joined; outbox = [:]; pendingApprovals = []; preparedBooks = [:]; persistQueues()
                defaults.set(0, forKey: Self.permissionsRevisionKey)
            }
            defaults.set(workspaceId, forKey: Self.workspaceKey)
            if enrolled.joinedOtherDevices == true {
                joinedOtherDevices = true
                status = HonbakoAutomationWorkspace.enrolledStatus(joinedOtherDevices: true)
            }
        }
        return true
    }

    func aiAuthorization(requestID: String, approved: Bool? = nil) async throws -> Data {
        try await HonbakoMCPAuthorizationGate.waitUntilActive {
            UIApplication.shared.applicationState == .active
        }
        guard let current = connection, usesManagedRemote, isEnabled else {
            throw HonbakoMCPAuthorizationError.connectionRequired
        }
        let body = HonbakoRemoteMCP.AuthorizationRequest(requestId: requestID, approved: approved)
        do {
            let data = try await request(endpoint: current.endpoint, path: "api/device/authorization", method: "POST",
                body: JSONEncoder().encode(body), token: current.deviceToken)
            guard isEnabled, connection?.deviceId == current.deviceId,
                  connection?.deviceToken == current.deviceToken, connection?.endpoint == current.endpoint else {
                throw HonbakoMCPAuthorizationError.connectionRequired
            }
            return data
        } catch BridgeError.unauthorized {
            throw HonbakoMCPAuthorizationError.connectionRequired
        } catch BridgeError.httpStatus(let status), BridgeError.refused(let status, _) {
            throw HonbakoMCPAuthorizationError.response(status: status)
        } catch is CancellationError {
            try Task.checkCancellation()
            throw HonbakoMCPAuthorizationError.inactive
        }
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

    /// Turns off this device only. Other devices on the same Pro purchase keep the AI connection.
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
        forgetConnection()
        errorMessage = cleared ? nil : "Disconnected on this device. Your companion was unreachable and may retain its last shared page and library snapshot until you clear them there."
        isDisconnecting = false
    }

    /// Removes every device and AI connection on this Pro purchase. Unlike turning off one
    /// device, nothing changes here unless the server confirms, so no device is left connected.
    func disconnectAllDevices() async {
        guard !isDisconnecting, usesManagedRemote, let connection else { return }
        HonbakoPageCoachingService.shared.stop()
        isDisconnecting = true
        pause()
        do {
            _ = try await request(endpoint: connection.endpoint, path: "api/device/disconnect-all", method: "POST",
                body: Data("{}".utf8), token: connection.deviceToken)
            forgetConnection()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn’t disconnect your devices. Check your internet connection and try again."
        }
        isDisconnecting = false
        if isEnabled { resume() }
    }

    /// Removes another device from this Pro purchase's workspace. Removing this device turns it off.
    func removeDevice(_ id: String) async {
        guard let current = connection, usesManagedRemote, isEnabled, !isRemovingDevice else { return }
        guard id != current.deviceId else { await disconnect(); return }
        isRemovingDevice = true
        defer { isRemovingDevice = false }
        do {
            _ = try await request(endpoint: current.endpoint, path: "api/device/remove", method: "POST",
                body: JSONEncoder().encode(HonbakoAutomationWorkspace.RemoveRequest(deviceId: id)), token: current.deviceToken)
            devices.removeAll { $0.deviceId == id }
        } catch BridgeError.httpStatus(404) {
            devices.removeAll { $0.deviceId == id }
        } catch {
            errorMessage = "Couldn’t remove that device. Check your internet connection and try again."
        }
    }

    private func forgetConnection() {
        isEnabled = false; defaults.set(false, forKey: Self.enabledKey)
        connection = nil; HonbakoAutomationCredentials.clear()
        pendingApprovals = []; preparedBooks = [:]; outbox = [:]; receipts = [:]
        devices = []; joinedOtherDevices = false; handledNotices = []
        defaults.removeObject(forKey: Self.workspaceKey)
        cachedLibrary = []; cachedSources = []; libraryStore = nil; persistQueues()
        status = "Not connected"
        session?.invalidateAndCancel(); session = nil
    }

    /// The first pairing, which the person has just agreed to, shares reading
    /// history; a later re-pair keeps whatever they chose since.
    private func adoptDefaultSharing() {
        if defaults.object(forKey: Self.sharingKey) == nil { defaults.set(true, forKey: Self.sharingKey) }
        sharesReadingPosition = defaults.bool(forKey: Self.sharingKey)
    }

    func setSharingReading(_ enabled: Bool) {
        guard sharesReadingPosition != enabled else { return }
        markPermissionsChanged()
        sharesReadingPosition = enabled
        if !enabled {
            outbox = outbox.filter { !$0.value.isHistoryResult }
            persistQueues()
        }
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

    var libraryAccessAllowed: Bool { defaults.object(forKey: "Honbako.MCP.LibraryAccess") as? Bool ?? true }
    var libraryChangesAllowed: Bool { defaults.object(forKey: "Honbako.MCP.LibraryChanges") as? Bool ?? true }
    var sourceChangesAllowed: Bool { defaults.object(forKey: "Honbako.MCP.SourceChanges") as? Bool ?? true }
    var pageAccessAllowed: Bool { defaults.object(forKey: "Honbako.MCP.PageAccess") as? Bool ?? true }
    var annotationsAllowed: Bool { defaults.object(forKey: "Honbako.MCP.Annotations") as? Bool ?? true }
    var permissions: [String: Bool] {
        ["libraryRead": libraryAccessAllowed, "readingRead": sharesReadingPosition, "pageRead": pageAccessAllowed,
         "libraryWrite": libraryChangesAllowed, "sourcesWrite": sourceChangesAllowed, "annotationsWrite": annotationsAllowed]
    }
    func setPermission(_ key: String, enabled: Bool) {
        guard ["LibraryAccess", "LibraryChanges", "SourceChanges", "PageAccess", "Annotations"].contains(key) else { return }
        objectWillChange.send()
        defaults.set(enabled, forKey: "Honbako.MCP." + key)
        markPermissionsChanged()
        invalidateState()
        if key == "PageAccess" || key == "Annotations" { HonbakoPageCoachingService.shared.refreshVisiblePage() }
        if canPoll {
            pollIdentity = UUID(); pollTask?.cancel(); pollTask = nil; resume()
        }
    }

    /// Remote switches belong to the whole account; this device saves its change on the next poll.
    private func markPermissionsChanged() {
        if usesSharedWorkspace { defaults.set(true, forKey: Self.permissionsPendingKey) }
    }
    private func pushPermissions(_ connection: Models.Connection) async throws {
        let body = try JSONEncoder().encode(HonbakoAutomationWorkspace.PermissionsUpdate(permissions: permissions))
        let data = try await request(endpoint: connection.endpoint, path: "api/device/permissions", method: "POST",
            body: body, token: connection.deviceToken)
        let saved = try JSONDecoder().decode(HonbakoAutomationWorkspace.PermissionsReply.self, from: data).permissions
        defaults.set(saved.revision, forKey: Self.permissionsRevisionKey)
        // A change made while this was in flight is pushed on the next poll.
        if saved.values == permissions { defaults.set(false, forKey: Self.permissionsPendingKey) }
    }
    /// Shows another device's switches here. The next snapshot carries them.
    private func adoptPermissions(_ values: [String: Bool], revision: Int) {
        objectWillChange.send()
        for (field, key) in HonbakoAutomationWorkspace.permissionKeys {
            if let value = values[field] { defaults.set(value, forKey: "Honbako.MCP." + key) }
        }
        if let reading = values["readingRead"], reading != sharesReadingPosition {
            sharesReadingPosition = reading
            defaults.set(reading, forKey: Self.sharingKey)
            if !reading {
                outbox = outbox.filter { !$0.value.isHistoryResult }; persistQueues()
                persistenceTask?.cancel(); persistenceTask = nil
            } else { persistReadingSoon() }
        }
        defaults.set(revision, forKey: Self.permissionsRevisionKey)
        HonbakoPageCoachingService.shared.refreshVisiblePage()
        invalidateState()
    }
    private func applyWorkspace(_ info: HonbakoAutomationWorkspace.Info, connection: Models.Connection) async {
        devices = info.devices
        switch HonbakoAutomationWorkspace.permissionSync(server: info.permissions,
            localRevision: defaults.integer(forKey: Self.permissionsRevisionKey),
            pendingPush: defaults.bool(forKey: Self.permissionsPendingKey)) {
        case .none: break
        case .push: try? await pushPermissions(connection)
        case .adopt(let values, let revision): adoptPermissions(values, revision: revision)
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
                if let change = approval.job.payload.change, approval.isSourceChange {
                    guard sourceChangesAllowed else { throw BridgeError.invalidResponse }
                    let result = try await HonbakoAutomationSources.apply(change)
                    try check(identity)
                    invalidateLibrary()
                    try await finish(jobID, status: "completed", result: result)
                    return
                }
                guard libraryChangesAllowed else { throw BridgeError.invalidResponse }
                if approval.isRemoval {
                    // Removal is naturally idempotent: a retried job reports
                    // books that are already gone as not present.
                    var removed: [Models.Match] = [], absent: [Models.Match] = []
                    for item in approval.items {
                        try check(identity)
                        let identifier = MangaIdentifier(sourceKey: item.sourceId, mangaKey: item.mangaId)
                        guard await isSaved(identifier) else { absent.append(item); continue }
                        await MangaManager.shared.removeFromLibrary(mangaIds: [identifier])
                        guard !(await isSaved(identifier)) else { throw BridgeError.importFailed }
                        removed.append(item)
                    }
                    invalidateLibrary()
                    try await finish(jobID, status: "completed", result: Models.RemoveResult(removed: removed, notPresent: absent))
                    status = "Removed approved books"
                    return
                }
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
            catch BridgeError.refused(409, "already_handled") {
                // Another device answered first. Its answer stands; this one never fails it.
                if identity == generation { noteHandled(jobID, title: approval.title, by: nil) }
            } catch {
                if identity == generation {
                    await fail(jobID, message: approval.isSourceChange
                        ? "The source change couldn’t be confirmed. Check Sources before retrying; a change may already have been applied."
                        : approval.isRemoval
                        ? "The approved books couldn’t all be removed. Some books may already have been removed. Check your library before retrying."
                        : "The approved books couldn’t all be added. Some books may already have been added. Check your library before retrying.")
                }
            }
        }
    }

    private func noteHandled(_ id: String, title: String, by device: String?) {
        removeApproval(id)
        handledNotices.removeAll { $0.id == id }
        handledNotices.insert(.init(id: id, title: title, deviceName: HonbakoAutomationWorkspace.deviceLabel(device)), at: 0)
        handledNotices = Array(handledNotices.prefix(5))
    }
    func handledNotice(for jobID: String) -> HonbakoAutomationWorkspace.HandledNotice? {
        handledNotices.first { $0.id == jobID }
    }

    func sourceName(for id: String) -> String { cachedSources.first { $0.id == id }?.name ?? id }

    func reject(jobID: String) async {
        guard canPoll, approvingJobID == nil else { return }
        removeApproval(jobID)
        outbox[jobID] = .init(status: "rejected"); persistQueues()
        await flushOutbox()
    }

    private func observe() {
        observers.append(NotificationCenter.default.addObserver(forName: HonbakoProStore.entitlementChangedNotification,
            object: nil, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in
                guard let self, usesManagedRemote else { return }
                pause(); resume()
            } })
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
        guard canPoll, pollTask == nil, !rejoinSharedWorkspaceIfNeeded() else { return }
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
                    let remote = usesManagedRemote
                    connection = nil; HonbakoAutomationCredentials.clear()
                    devices = []; joinedOtherDevices = false; defaults.removeObject(forKey: Self.workspaceKey)
                    status = remote ? "This device was removed from MCP Server. Turn on Connect Remotely to connect it again." : "Pair with your companion again"
                    break
                } catch BridgeError.httpStatus(402) {
                    guard !Task.isCancelled, identity == generation else { break }
                    status = "Remote MCP requires Pro"
                    errorMessage = "Your remote server is paused. Restore or renew Pro to reconnect."
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
        if usesSharedWorkspace, defaults.bool(forKey: Self.permissionsPendingKey) {
            try? await pushPermissions(connection)
            try check(identity)
        }
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
        let decoded = try JSONDecoder().decode(Models.Jobs.self, from: data), jobs = decoded.jobs
        try check(identity)
        let live = Set(jobs.map(\.id))
        let answered = HonbakoAutomationWorkspace.handledElsewhere(pending: pendingApprovals.map(\.id).filter { $0 != approvingJobID },
            handled: decoded.handled ?? [], live: live)
        for approval in pendingApprovals where answered[approval.id] != nil {
            noteHandled(approval.id, title: approval.title, by: answered[approval.id])
        }
        if let workspace = decoded.workspace {
            await applyWorkspace(workspace, connection: connection)
            try check(identity)
        }
        pendingApprovals.removeAll { !live.contains($0.id) && $0.id != approvingJobID }
        preparedBooks = preparedBooks.filter { live.contains($0.key) || $0.key == approvingJobID }
        let readyJobs = jobs.filter { job in
            outbox[job.id] == nil && job.id != approvingJobID && !pendingApprovals.contains(where: { $0.id == job.id })
        }
        for job in readyJobs.prefix(10) {
            try check(identity)
            guard outbox[job.id] == nil, job.id != approvingJobID,
                  !pendingApprovals.contains(where: { $0.id == job.id }) else { continue }
            do {
                try HonbakoAutomationPolicy.validate(job)
                switch job.kind {
                case "catalog.search":
                    // Searching runs through the person's own sources, so it
                    // follows Read Library and Sources.
                    guard libraryAccessAllowed else { throw BridgeError.invalidResponse }
                    try await search(job, identity: identity)
                case "history.read":
                    guard sharesReadingPosition, let before = job.payload.before else { throw BridgeError.invalidResponse }
                    let result = try await CoreDataManager.shared.container.performBackgroundTask { context in
                        try HonbakoAutomationHistory.page(offset: job.payload.offset ?? 0, limit: job.payload.limit ?? 50, before: before, context: context)
                    }
                    try check(identity)
                    guard sharesReadingPosition else { throw BridgeError.invalidResponse }
                    try await finish(job.id, status: "completed", result: result)
                case "sources.catalog":
                    guard libraryAccessAllowed else { throw BridgeError.invalidResponse }
                    let result = await HonbakoAutomationSources.catalog(offset: job.payload.offset ?? 0, limit: job.payload.limit ?? 100)
                    try check(identity)
                    guard libraryAccessAllowed else { throw BridgeError.invalidResponse }
                    try await finish(job.id, status: "completed", result: result)
                case "sources.change":
                    guard sourceChangesAllowed, let change = job.payload.change else { throw BridgeError.invalidResponse }
                    let name = try await HonbakoAutomationSources.review(change)
                    try check(identity)
                    try await postStatus(jobID: job.id, update: .init(status: "awaitingApproval"), connection: connection)
                    pendingApprovals.append(.init(job: job, items: [.init(sourceId: change.sourceId ?? "repository", mangaId: "source", title: name)]))
                case "library.remove":
                    guard libraryChangesAllowed else { throw BridgeError.invalidResponse }
                    try await prepareRemoval(job, identity: identity)
                default:
                    guard libraryChangesAllowed else { throw BridgeError.invalidResponse }
                    try await prepareApproval(job, identity: identity)
                }
            } catch is CancellationError { throw CancellationError() }
            catch BridgeError.refused(409, "already_handled") { removeApproval(job.id) }
            catch { await fail(job.id, message: "This request is unavailable, disabled in MCP permissions, or has invalid items.") }
        }
        status = pendingApprovals.isEmpty ? "Connected" : "Requests are waiting for your approval"
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
        let accessibleLibrary = libraryAccessAllowed ? cachedLibrary : []
        let exportedLibrary = sharesReadingPosition ? accessibleLibrary : accessibleLibrary.map { book in
            var redacted = book
            redacted.lastReadPage = nil
            return redacted
        }
        var state = Models.State(generatedAt: nextSnapshotTimestamp(), library: exportedLibrary, sources: libraryAccessAllowed ? cachedSources : [],
            reading: sharesReadingPosition ? lastReading : nil, libraryTruncated: libraryTruncated, sourcesTruncated: sourcesTruncated)
        // Keep a large collection below the companion's one-MiB request limit.
        while try JSONEncoder().encode(state).count > 900_000, !state.library.isEmpty {
            state = Models.State(generatedAt: state.generatedAt, library: Array(state.library.dropLast(100)),
                sources: state.sources, reading: state.reading, libraryTruncated: true, sourcesTruncated: state.sourcesTruncated)
        }
        state.readingHistoryAccess = sharesReadingPosition
        state.automationCapabilities = ["reading.history", "sources.manage", "library.remove"]
        state.permissions = permissions
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
    /// Removal needs no network: titles come from the saved library the
    /// person is about to change, so the approval shows exactly what goes.
    private func prepareRemoval(_ job: Models.Job, identity: UUID) async throws {
        guard let connection, let items = job.payload.items else { throw BridgeError.invalidResponse }
        let titles = Dictionary(cachedLibrary.map { (Models.Item(sourceId: $0.sourceId, mangaId: $0.mangaId), $0) },
            uniquingKeysWith: { first, _ in first })
        try await postStatus(jobID: job.id, update: .init(status: "awaitingApproval"), connection: connection)
        try check(identity)
        pendingApprovals.append(.init(job: job, items: items.map { item in
            .init(sourceId: item.sourceId, mangaId: item.mangaId, title: titles[item]?.title ?? item.mangaId, author: titles[item]?.author)
        }))
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
            } catch BridgeError.conflict, BridgeError.refused(409, _) {
                guard !Task.isCancelled, identity == generation, canPoll else { break }
                outbox[id] = nil; persistQueues()
            } catch BridgeError.httpStatus(404) {
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
        if [409, 429].contains(response.statusCode), let code = try? JSONDecoder().decode(ErrorBody.self, from: data).error.code,
           ["purchase_mismatch", "device_limit", "rate_limited", "already_handled"].contains(code) {
            throw BridgeError.refused(response.statusCode, code)
        }
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
        let data: Data
        do {
            data = try await request(endpoint: current.endpoint, path: path, method: method, body: body, token: current.deviceToken)
        } catch BridgeError.httpStatus(410) {
            throw HonbakoPageCoachingService.CoachingError.sessionClosed
        }
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

    private enum BridgeError: Error {
        case invalidResponse, unauthorized, conflict, unavailableSource, importFailed, httpStatus(Int)
        /// A 409 or 429 whose body names why, such as `purchase_mismatch` or `device_limit`.
        case refused(Int, String)
    }
    private struct ErrorBody: Decodable {
        struct Detail: Decodable { let code: String }
        let error: Detail
    }
}
#endif
