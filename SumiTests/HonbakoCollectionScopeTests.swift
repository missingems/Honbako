@testable import Sumi
import CoreData
import Foundation
import Testing

@MainActor
@Suite(.serialized)
struct HonbakoCollectionScopeTests {
    @Test("Local files and each supported personal server survive stored configuration loading")
    func personalCollectionsLoad() async throws {
        let server = CustomSourceConfig.KeyNameServer(key: "my-library", name: "My Library", server: "https://books.example/library")
        let configs: [CustomSourceConfig] = [.local, .komga(server), .kavita(server), .suwayomi(server)]
        for config in configs {
            let decoded = try CustomSourceConfig(from: config.encode())
            #expect(decoded.isPersonalCollection)
            let stored = record(config: decoded.encode())
            #expect(await stored.toNewSource() != nil)
            #expect(stored.toInfo() != nil)
        }
    }

    @Test("Previously installed public catalogs and demo sources cannot load from backups or existing storage", .enabled(if: !HonbakoSourceScope.externalSourcesEnabled))
    func externalConfigsStayUnavailable() async {
        let configs: [CustomSourceConfig] = [.demo, .honbakoMangaDex]
        for config in configs {
            #expect(!config.isPersonalCollection)
            let stored = record(config: config.encode())
            #expect(await stored.toNewSource() == nil)
            #expect(stored.toInfo() == nil)
        }
    }

    @Test("Package records cannot gain local-reader privileges through a reserved source identifier", .enabled(if: !HonbakoSourceScope.externalSourcesEnabled))
    func sourcePackagesStayUnavailable() async {
        for version in ["0.6", "0.7"] {
            let stored = record(config: nil, apiVersion: version, path: "Sources/untrusted")
            #expect(stored.toSource() == nil)
            #expect(await stored.toNewSource() == nil)
            #expect(stored.toInfo() == nil)
        }
    }

    @Test("Source-list restoration cannot re-enable external lists even when unavailable lists are accepted", .enabled(if: !HonbakoSourceScope.externalSourcesEnabled))
    func sourceListRestoreIsRejected() async throws {
        let before = await SourceManager.shared.getSourceListURLs()
        let url = try #require(URL(string: "https://source-fixture.invalid/catalog.json"))
        #expect(await SourceManager.shared.addSourceList(url: url, allowUnavailable: true) == false)
        #expect(await SourceManager.shared.getSourceListURLs() == before)
        #expect(before.isEmpty)
    }

    @Test("External package ingestion and catalog creation are rejected before installation", .enabled(if: !HonbakoSourceScope.externalSourcesEnabled))
    func externalInstallationIsRejected() async throws {
        let url = try #require(URL(string: "https://source-fixture.invalid/package.aix"))
        #expect(await SourceManager.shared.importSource(from: url) == nil)
        #expect(await SourceManager.shared.installExternalSources(keys: ["multi.mangadex"]) == nil)
        #expect(await SourceManager.shared.createCustomSource(.honbakoMangaDex) == nil)
        #expect(await SourceManager.shared.createCustomSource(.demo) == nil)
    }

    private func record(config: Data?, apiVersion: String? = nil, path: String? = nil) -> SourceObjectData {
        let entity = NSEntityDescription()
        entity.name = "ScopeFixture"
        let object = NSManagedObject(entity: entity, insertInto: nil)
        return SourceObjectData(objectID: object.objectID, id: "local", apiVersion: apiVersion,
                                path: path, listing: 0, customSource: config)
    }
}
