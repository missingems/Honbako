@testable import Sumi
import Foundation
import Testing

@Suite struct HonbakoAutomationWorkspaceTests {
    private typealias Workspace = HonbakoAutomationWorkspace
    private typealias Models = HonbakoAutomationModels

    @Test("Account permissions: an unsaved local change is pushed, another revision is adopted, an empty workspace is seeded")
    func permissionSync() {
        let server = Workspace.Permissions(values: ["libraryRead": false, "readingRead": true], revision: 4)
        #expect(Workspace.permissionSync(server: server, localRevision: 4, pendingPush: false) == .none)
        #expect(Workspace.permissionSync(server: server, localRevision: 2, pendingPush: false) == .adopt(server.values, revision: 4))
        // A workspace that started over after Disconnect All has a lower revision; it still wins.
        #expect(Workspace.permissionSync(server: server, localRevision: 9, pendingPush: false) == .adopt(server.values, revision: 4))
        #expect(Workspace.permissionSync(server: server, localRevision: 2, pendingPush: true) == .push)
        #expect(Workspace.permissionSync(server: nil, localRevision: 0, pendingPush: false) == .push)
    }

    @Test("Every account switch maps to one of this device’s settings")
    func permissionKeysCoverTheSnapshot() {
        let snapshotFields: Set = ["libraryRead", "readingRead", "pageRead", "libraryWrite", "sourcesWrite", "annotationsWrite"]
        #expect(Set(Workspace.permissionKeys.keys).union(["readingRead"]) == snapshotFields)
        #expect(Set(Workspace.permissionKeys.values) == ["LibraryAccess", "PageAccess", "LibraryChanges", "SourceChanges", "Annotations"])
    }

    @Test("An approval that left the queue shows who handled it; one still queued or unexplained does not")
    func handledElsewhere() {
        let handled = [Workspace.Handled(id: "a", status: "completed", handledBy: "iPad"),
                       Workspace.Handled(id: "b", status: "rejected", handledBy: "Honbako on iPhone"),
                       Workspace.Handled(id: "c", status: "rejected", handledBy: nil)]
        let result = Workspace.handledElsewhere(pending: ["a", "b", "c", "d", "e"], handled: handled, live: ["e"])
        #expect(result == ["a": "iPad", "b": "iPhone", "c": String(localized: "another device")])
        #expect(Workspace.handledElsewhere(pending: ["a"], handled: handled, live: ["a"]).isEmpty)
    }

    @Test("Device names drop the old Honbako prefix and parse server timestamps")
    func deviceDisplay() throws {
        #expect(Workspace.deviceLabel("Honbako on iPhone") == "iPhone")
        #expect(Workspace.deviceLabel("iPad") == "iPad")
        #expect(Workspace.deviceLabel("  ") == String(localized: "another device"))
        let json = Data(#"{"deviceId":"d","name":"Honbako on iPad","lastActive":"2026-10-31T09:15:02.123Z","thisDevice":false,"current":true}"#.utf8)
        let device = try JSONDecoder().decode(Workspace.Device.self, from: json)
        #expect(device.displayName == "iPad")
        #expect(abs((device.lastActiveDate?.timeIntervalSince1970 ?? 0) - 1_793_438_102.123) < 0.001)
        let plain = Workspace.Device(deviceId: "e", name: "iPhone", lastActive: "2026-10-31T09:15:02Z", thisDevice: true, current: false)
        #expect(plain.lastActiveDate == Date(timeIntervalSince1970: 1_793_438_102))
    }

    @Test("Only a managed remote pairing without a shared workspace re-enrolls, once per launch")
    func rejoin() {
        #expect(Workspace.needsRejoin(managed: true, enabled: true, workspaceId: nil, attempted: false))
        #expect(!Workspace.needsRejoin(managed: true, enabled: true, workspaceId: "w", attempted: false))
        #expect(!Workspace.needsRejoin(managed: true, enabled: true, workspaceId: nil, attempted: true))
        #expect(!Workspace.needsRejoin(managed: false, enabled: true, workspaceId: nil, attempted: false))
        #expect(!Workspace.needsRejoin(managed: true, enabled: false, workspaceId: nil, attempted: false))
    }

    @Test("A device that joins says so instead of asking to connect an AI again")
    func enrolledStatus() throws {
        let joined = try JSONDecoder().decode(HonbakoRemoteMCP.Enrolled.self, from: Data(
            #"{"deviceId":"d","deviceToken":"t","endpoint":"https://mcp.honbako.xyz/remote","workspaceId":"w","joinedOtherDevices":true}"#.utf8))
        #expect(Workspace.enrolledStatus(joinedOtherDevices: joined.joinedOtherDevices) == String(localized: "Connected with your other devices"))
        // An older server sends neither field; the pairing still works and is retried later.
        let older = try JSONDecoder().decode(HonbakoRemoteMCP.Enrolled.self, from: Data(
            #"{"deviceId":"d","deviceToken":"t","endpoint":"https://mcp.honbako.xyz/remote"}"#.utf8))
        #expect(older.workspaceId == nil)
        #expect(Workspace.enrolledStatus(joinedOtherDevices: older.joinedOtherDevices) == String(localized: "Remote MCP enabled"))
    }

    @Test("A poll carries the device list, the account’s switches and approvals handled elsewhere")
    func pollDecodes() throws {
        let json = #"""
        {"jobs":[],"handled":[{"id":"j","status":"completed","handledBy":"iPad"}],
         "workspace":{"workspaceId":"w","deviceId":"me","currentDeviceId":"pad","deviceLimit":5,
           "devices":[{"deviceId":"me","name":"iPhone","lastActive":null,"thisDevice":true,"current":false},
                      {"deviceId":"pad","name":"iPad","lastActive":"2026-10-31T09:15:02.123Z","thisDevice":false,"current":true}],
           "permissions":{"values":{"pageRead":false},"revision":2}}}
        """#
        let decoded = try JSONDecoder().decode(Models.Jobs.self, from: Data(json.utf8))
        #expect(decoded.handled == [.init(id: "j", status: "completed", handledBy: "iPad")])
        #expect(decoded.workspace?.devices.map(\.displayName) == ["iPhone", "iPad"])
        #expect(decoded.workspace?.permissions == .init(values: ["pageRead": false], revision: 2))
        // A local Mac companion's poll has neither, and still decodes.
        let local = try JSONDecoder().decode(Models.Jobs.self, from: Data(#"{"jobs":[]}"#.utf8))
        #expect(local.workspace == nil && local.handled == nil)
    }
}
