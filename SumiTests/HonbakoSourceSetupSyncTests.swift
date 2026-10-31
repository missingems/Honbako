@testable import Sumi
import Foundation
import Testing

struct HonbakoSourceSetupPolicyTests {
    @Test("Source metadata never accepts credentials, query tokens, fragments or provider impersonation")
    func rejectsUnsafeMetadata() {
        for server in ["https://name:password@server.example", "https://server.example?key=secret", "https://server.example/#token"] {
            #expect(!HonbakoSourceSetupPolicy.validate(.init(id: "komga.home", kind: .komga, name: "Home", serverURL: server)))
        }
        #expect(HonbakoSourceSetupPolicy.validate(.init(id: "komga.home", kind: .komga, name: "Home", serverURL: "http://192.168.1.2:25600/library")))
        #expect(HonbakoSourceSetupPolicy.validate(.init(id: "kavita.home", kind: .kavita, name: "Home", serverURL: "https://kavita.example")))
        #expect(HonbakoSourceSetupPolicy.validate(.init(id: "suwayomi.home", kind: .suwayomi, name: "Home", serverURL: "http://server.local:4567")))
        #expect(!HonbakoSourceSetupPolicy.validate(.init(id: "honbako.mangadex", kind: .komga, name: "Other", serverURL: "https://server.example")))
        #expect(!HonbakoSourceSetupPolicy.validate(.init(id: "local", kind: .extensionPackage, name: "Other")))
        #expect(!HonbakoSourceSetupPolicy.validate(.init(id: "not-native", kind: .mangaDex, name: "Other")))
        #expect(HonbakoSourceSetupPolicy.safeURL("http://repository.example/index.json") == nil)
    }

    @Test("Bounded payloads round-trip only under their own record keys and do not include unknown preference fields")
    func boundedSchema() throws {
        let record = HonbakoSourceSetupRecord(id: "en.original", kind: .extensionPackage, name: "Original", version: 4,
            repositoryURL: "https://sources.example/index.json", packageURL: "https://sources.example/original-4.aix", packageSHA256: String(repeating: "a", count: 64))
        let data = try #require(HonbakoSourceSetupPolicy.encode(record))
        #expect(HonbakoSourceSetupPolicy.decode(data, key: HonbakoSourceSetupPolicy.key(for: record)) == record)
        #expect(HonbakoSourceSetupPolicy.decode(data, key: "Honbako.SourceSetup.v1.source.other") == nil)
        #expect(HonbakoSourceSetupPolicy.decode(Data(repeating: 0, count: HonbakoSourceSetupPolicy.maxRecordBytes + 1), key: HonbakoSourceSetupPolicy.key(for: record)) == nil)
        var oversized = record; oversized.name = String(repeating: "x", count: 501)
        #expect(HonbakoSourceSetupPolicy.encode(oversized) == nil)
        let text = try #require(String(data: data, encoding: .utf8))
        for forbidden in ["password", "cookie", "authorization", "apiKey", "settings"] { #expect(!text.contains(forbidden)) }
    }

    @Test("Package restore rejects replacement IDs, newer versions and changed bytes")
    func exactPackageIdentity() {
        #expect(HonbakoSourceSetupPolicy.matchesPackage(id: "en.original", version: 4, digest: "saved", expectedID: "en.original", expectedVersion: 4, expectedDigest: "saved"))
        #expect(!HonbakoSourceSetupPolicy.matchesPackage(id: "en.other", version: 4, digest: "saved", expectedID: "en.original", expectedVersion: 4, expectedDigest: "saved"))
        #expect(!HonbakoSourceSetupPolicy.matchesPackage(id: "en.original", version: 5, digest: "saved", expectedID: "en.original", expectedVersion: 4, expectedDigest: "saved"))
        #expect(!HonbakoSourceSetupPolicy.matchesPackage(id: "en.original", version: 4, digest: "changed", expectedID: "en.original", expectedVersion: 4, expectedDigest: "saved"))
    }

    @Test("Unit tests and all Sumi/Honbako fixture launches cannot create a real cloud writer")
    func blocksLiveFixtureCloud() {
        #expect(HonbakoSourceSetupPolicy.permitsLiveStore(arguments: ["Sumi"], environment: [:]))
        for flag in ["--sumi-onboarding", "--honbako-preview", "-sumi-book-fixture", "screenshot-test"] {
            #expect(!HonbakoSourceSetupPolicy.permitsLiveStore(arguments: ["Sumi", flag], environment: [:]))
        }
        for key in ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"] {
            #expect(!HonbakoSourceSetupPolicy.permitsLiveStore(arguments: ["Sumi"], environment: [key: "fixture"]))
        }
    }
}

@MainActor
struct HonbakoSourceSetupSyncTests {
    @MainActor private final class MemoryStore: HonbakoSourceSetupCloudStore {
        var values: [String: Data] = [:]
        var writes = 0
        var keys: [String] { Array(values.keys) }
        func data(forKey key: String) -> Data? { values[key] }
        func set(_ value: Data, forKey key: String) { values[key] = value; writes += 1 }
        func synchronize() -> Bool { true }
        func seed(_ record: HonbakoSourceSetupRecord) { values[HonbakoSourceSetupPolicy.key(for: record)] = HonbakoSourceSetupPolicy.encode(record) }
    }
    @MainActor private final class State {
        var enabled = true
        var account = true
        var local: [HonbakoSourceSetupRecord] = []
        var libraryIDs: [String] = []
        var restoredConnections: [HonbakoSourceSetupRecord] = []
        var packageCalls = 0
        var packageSucceeds = true
    }
    private func service(_ cloud: MemoryStore, _ state: State) -> HonbakoSourceSetupSync {
        .init(store: cloud, enabled: { state.enabled }, accountAvailable: { state.account },
            localRecords: { state.local }, restoreConnections: { records in
                state.restoredConnections = records
                for record in records where record.kind != .extensionPackage && record.kind != .repository && !state.local.contains(where: { $0.id == record.id }) {
                    state.local.append(record)
                }
            }, missingLibraryIDs: { state.libraryIDs.filter { id in !state.local.contains(where: { $0.id == id }) } },
            restorePackage: { record in state.packageCalls += 1; if state.packageSucceeds { state.local.append(record) }; return state.packageSucceeds })
    }

    @Test("Reinstall and transiently empty local databases never erase a cloud setup record")
    func noBlankOverwrite() async throws {
        let cloud = MemoryStore(), state = State()
        let saved = HonbakoSourceSetupRecord(id: "en.original", kind: .extensionPackage, name: "Original", version: 1,
            repositoryURL: "https://sources.example/index.json", packageURL: "https://sources.example/original.aix", packageSHA256: String(repeating: "a", count: 64))
        cloud.seed(saved); state.libraryIDs = [saved.id]
        let sync = service(cloud, state)
        await sync.refresh()
        #expect(cloud.writes == 0)
        #expect(state.packageCalls == 0)
        #expect(sync.missing.first?.canRestorePackage == true)
        state.local = [saved]; await sync.refresh()
        state.local = []; await sync.refresh()
        #expect(cloud.writes == 0)
        #expect(HonbakoSourceSetupPolicy.decode(try #require(cloud.values.values.first), key: HonbakoSourceSetupPolicy.key(for: saved))?.removed == false)
        await sync.restore(try #require(sync.missing.first))
        #expect(state.packageCalls == 1)
        #expect(sync.missing.isEmpty)
    }

    @Test("All personal server providers restore safe connection metadata while existing local configuration wins")
    func personalConnectionsMerge() async throws {
        let cloud = MemoryStore(), state = State()
        let existing = HonbakoSourceSetupRecord(id: "komga.home", kind: .komga, name: "Local choice", serverURL: "http://local.example")
        state.local = [existing]
        for kind in [HonbakoSourceSetupRecord.Kind.komga, .kavita, .suwayomi] {
            cloud.seed(.init(id: kind.rawValue + ".home", kind: kind, name: "Cloud choice", serverURL: "https://cloud.example"))
        }
        let sync = service(cloud, state); await sync.refresh()
        #expect(state.local.count == 3)
        #expect(state.local.first(where: { $0.id == existing.id })?.serverURL == existing.serverURL)
        #expect(sync.personalServers.count == 3)
        #expect(cloud.writes == 0)
    }

    @Test("The known built-in MangaDex source reconnects without a prior backup or an executable package")
    func reconnectsKnownBundledSource() async throws {
        let cloud = MemoryStore(), state = State(); state.libraryIDs = ["honbako.mangadex"]
        let sync = service(cloud, state); await sync.refresh()
        let recovery = try #require(sync.missing.first)
        #expect(recovery.name == "MangaDex")
        if recovery.canReconnectBundledSource {
            await sync.restore(recovery)
            #expect(state.local.map(\.id) == ["honbako.mangadex"])
            #expect(sync.missing.isEmpty)
        } else { #expect(state.local.isEmpty) }
        #expect(state.packageCalls == 0)
    }

    @Test("A missing built-in MangaDex source reconnects locally while iCloud is temporarily unavailable")
    func reconnectsBuiltInWithoutAvailableCloudAccount() async throws {
        let cloud = MemoryStore(), state = State()
        state.libraryIDs = ["honbako.mangadex"]
        state.account = false
        let sync = service(cloud, state)
        await sync.refresh()
        let recovery = try #require(sync.missing.first)
        #expect(recovery.id == "honbako.mangadex")
        #expect(recovery.record == nil)
        #expect(!sync.cloudAvailable)
        if recovery.canReconnectBundledSource {
            await sync.restore(recovery)
            #expect(state.local.map(\.id) == ["honbako.mangadex"])
            #expect(state.local.first?.kind == .mangaDex)
            #expect(sync.missing.isEmpty)
        }
        #expect(state.packageCalls == 0)
        #expect(cloud.writes == 0)
        #expect(cloud.values.isEmpty)
    }

    @Test("Devices with different local server settings do not bounce cloud metadata back and forth")
    func conflictingLocalConnectionsDoNotPingPong() async throws {
        let cloud = MemoryStore(), first = State(), second = State()
        let original = HonbakoSourceSetupRecord(id: "komga.home", kind: .komga, name: "Saved server", serverURL: "https://saved.example")
        cloud.seed(original)
        first.local = [.init(id: original.id, kind: .komga, name: "First device", serverURL: "http://first.local")]
        second.local = [.init(id: original.id, kind: .komga, name: "Second device", serverURL: "http://second.local")]
        let firstSync = service(cloud, first), secondSync = service(cloud, second)
        await firstSync.refresh()
        await secondSync.refresh()
        #expect(cloud.writes == 0)
        #expect(first.local.first?.serverURL == "http://first.local")
        #expect(second.local.first?.serverURL == "http://second.local")

        // A deliberate edit on one device updates the backup once. Receiving that
        // update on the other device must preserve its own local configuration.
        first.local[0].serverURL = "https://edited-first.example"
        await firstSync.refresh()
        #expect(cloud.writes == 1)
        for _ in 0..<3 {
            await secondSync.refresh()
            await firstSync.refresh()
        }
        #expect(cloud.writes == 1)
        #expect(second.local.first?.serverURL == "http://second.local")
        let key = HonbakoSourceSetupPolicy.key(for: original)
        let firstBackup = try #require(cloud.values[key])
        #expect(HonbakoSourceSetupPolicy.decode(firstBackup, key: key)?.serverURL == "https://edited-first.example")

        second.local[0].serverURL = "https://edited-second.example"
        await secondSync.refresh()
        #expect(cloud.writes == 2)
        for _ in 0..<3 {
            await firstSync.refresh()
            await secondSync.refresh()
        }
        #expect(cloud.writes == 2)
        #expect(first.local.first?.serverURL == "https://edited-first.example")
        let secondBackup = try #require(cloud.values[key])
        #expect(HonbakoSourceSetupPolicy.decode(secondBackup, key: key)?.serverURL == "https://edited-second.example")
    }

    @Test("Missing legacy setup is reported without guessing a repository or installing a package")
    func missingUnknownSource() async {
        let cloud = MemoryStore(), state = State(); state.libraryIDs = ["multi.legacy"]
        let sync = service(cloud, state); await sync.refresh()
        #expect(sync.missing.map(\.id) == ["multi.legacy"])
        #expect(sync.missing.first?.record == nil)
        #expect(sync.missing.first?.canRestorePackage == false)
        #expect(state.packageCalls == 0)
    }

    @Test("Disabling sync or losing the iCloud account stops metadata reads, writes and restore")
    func respectsSyncAccountScope() async {
        let cloud = MemoryStore(), state = State(); state.local = [.init(id: "local", kind: .local, name: "Files")]
        state.enabled = false
        let sync = service(cloud, state); await sync.refresh()
        #expect(cloud.values.isEmpty); #expect(state.restoredConnections.isEmpty)
        state.enabled = true; state.account = false; await sync.refresh()
        #expect(cloud.values.isEmpty); #expect(state.restoredConnections.isEmpty)
        state.account = true; await sync.refresh()
        #expect(cloud.writes == 1)
    }

    @Test("Only explicit removal creates a tombstone, and an oversized setup cannot exceed the record budget")
    func explicitRemovalAndQuota() async throws {
        let cloud = MemoryStore(), state = State()
        let record = HonbakoSourceSetupRecord(id: "en.original", kind: .extensionPackage, name: "Original", version: 1)
        cloud.seed(record); state.local = [record]
        let sync = service(cloud, state); await sync.refresh()
        state.local = []; await sync.recordRemoval(id: record.id, repository: false)
        #expect(HonbakoSourceSetupPolicy.decode(try #require(cloud.values[HonbakoSourceSetupPolicy.key(for: record)]), key: HonbakoSourceSetupPolicy.key(for: record))?.removed == true)
        let full = MemoryStore(), other = State()
        for index in 0..<HonbakoSourceSetupPolicy.maxRecords { full.seed(.init(id: "en.source.\(index)", kind: .extensionPackage, name: "Saved")) }
        other.local = [.init(id: "en.additional", kind: .extensionPackage, name: "Additional")]
        let fullSync = service(full, other); await fullSync.refresh()
        #expect(full.writes == 0); #expect(fullSync.lastError != nil)
    }
}
