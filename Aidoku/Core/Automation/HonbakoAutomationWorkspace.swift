#if SUMI
import Foundation

/// One hosted MCP workspace per Pro purchase, shared by up to five of the person's devices.
/// These decisions are kept free of the service so they can be tested on their own.
enum HonbakoAutomationWorkspace {
    struct Device: Codable, Identifiable, Equatable, Sendable {
        let deviceId: String
        let name: String
        let lastActive: String?
        let thisDevice: Bool
        let current: Bool
        var id: String { deviceId }
        var displayName: String { HonbakoAutomationWorkspace.deviceLabel(name) }
        var lastActiveDate: Date? {
            guard let lastActive else { return nil }
            return (try? Date(lastActive, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
                ?? (try? Date(lastActive, strategy: .iso8601))
        }
    }
    struct Permissions: Codable, Equatable, Sendable {
        let values: [String: Bool]
        let revision: Int
    }
    struct Info: Decodable, Equatable, Sendable {
        let workspaceId: String
        let deviceId: String
        let currentDeviceId: String?
        let devices: [Device]
        let permissions: Permissions?
    }
    /// An approval another device answered within the last hour.
    struct Handled: Decodable, Equatable, Sendable {
        let id: String
        let status: String
        let handledBy: String?
    }
    struct HandledNotice: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        let deviceName: String
    }
    struct PermissionsUpdate: Encodable { let permissions: [String: Bool] }
    struct PermissionsReply: Decodable { let permissions: Permissions }
    struct RemoveRequest: Encodable { let deviceId: String }

    /// Server permission names and the settings keys that store them on this device.
    /// Reading access is `readingRead`, stored as the reading-sharing switch.
    static let permissionKeys = ["libraryRead": "LibraryAccess", "pageRead": "PageAccess", "libraryWrite": "LibraryChanges",
                                 "sourcesWrite": "SourceChanges", "annotationsWrite": "Annotations"]

    enum PermissionSync: Equatable {
        case none, push
        case adopt([String: Bool], revision: Int)
    }
    /// One set of switches for the account. A change made here and not yet saved wins;
    /// otherwise any other revision (another device's change, or a workspace that started over)
    /// replaces this device's switches. A workspace without switches takes this device's.
    static func permissionSync(server: Permissions?, localRevision: Int, pendingPush: Bool) -> PermissionSync {
        guard !pendingPush, let server else { return .push }
        return server.revision == localRevision ? .none : .adopt(server.values, revision: server.revision)
    }

    /// Approvals shown here that left the queue because another device answered them, by job ID.
    static func handledElsewhere(pending: [String], handled: [Handled], live: Set<String>) -> [String: String] {
        var result: [String: String] = [:]
        for id in pending where !live.contains(id) {
            if let answer = handled.first(where: { $0.id == id }) { result[id] = deviceLabel(answer.handledBy) }
        }
        return result
    }

    /// Devices enrolled before this release are named "Honbako on iPhone".
    static func deviceLabel(_ name: String?) -> String {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return String(localized: "another device")
        }
        return name.hasPrefix("Honbako on ") ? String(name.dropFirst("Honbako on ".count)) : name
    }

    /// A remote pairing made before shared workspaces enrolls once more, so it joins the
    /// other devices on its Pro purchase. The device whose ID became the workspace keeps its token.
    static func needsRejoin(managed: Bool, enabled: Bool, workspaceId: String?, attempted: Bool) -> Bool {
        managed && enabled && workspaceId == nil && !attempted
    }

    /// What to show after this device enrolls.
    static func enrolledStatus(joinedOtherDevices: Bool?) -> String {
        joinedOtherDevices == true ? String(localized: "Connected with your other devices") : String(localized: "Remote MCP enabled")
    }
}
#endif
