@testable import Sumi
import AidokuRunner
import CoreData
import Foundation
import Testing

@MainActor
@Suite(.serialized, .enabled(if: HonbakoSourceScope.externalSourcesEnabled))
struct HonbakoExternalBetaTests {
    @Test("Explicit external beta restores native catalog configs without enabling the private Pro override")
    func storedCatalogConfigurationLoads() async {
        let entity = NSEntityDescription()
        entity.name = "ExternalScopeFixture"
        let object = NSManagedObject(entity: entity, insertInto: nil)
        let stored = SourceObjectData(objectID: object.objectID, id: HonbakoMangaDexRunner.sourceKey,
            apiVersion: nil, path: nil, listing: 0, customSource: CustomSourceConfig.honbakoMangaDex.encode())
        #expect(await stored.toNewSource()?.key == HonbakoMangaDexRunner.sourceKey)
        #expect(stored.toInfo()?.sourceId == HonbakoMangaDexRunner.sourceKey)
        #expect(!HonbakoProStore.personalFeaturesEnabled)
    }

    @Test("An external list can be deliberately retained and removed without installing any sources")
    func sourceListLifecycle() async throws {
        let before = Set(await SourceManager.shared.getSourceInfos().map(\.sourceId))
        let url = try #require(URL(string: "http://127.0.0.1:9/honbako-list-fixture.json"))
        let added = await SourceManager.shared.addSourceList(url: url, allowUnavailable: true)
        let saved = await SourceManager.shared.getSourceListURLs()
        await SourceManager.shared.removeSourceList(url: url)
        #expect(added)
        #expect(saved.contains(url))
        #expect(!(await SourceManager.shared.getSourceListURLs()).contains(url))
        #expect(Set(await SourceManager.shared.getSourceInfos().map(\.sourceId)) == before)
    }

    @Test("An allowlisted native descriptor installs its compiled connector and can be removed")
    func explicitNativeInstallation() async throws {
        let descriptor = try JSONDecoder().decode(ExternalSourceInfo.self, from: Data(#"{"id":"honbako.mangadex","name":"Fixture Native Catalog","version":1,"nativeRunner":"honbako.mangadex.rest.v1","languages":["en"]}"#.utf8))
        let key = HonbakoMangaDexRunner.sourceKey
        let existed = await SourceManager.shared.source(for: key) != nil
        let installed = await SourceManager.shared.installExternalSource(descriptor)
        let loaded = await SourceManager.shared.source(for: key)
        if !existed { await SourceManager.shared.remove(sourceKey: key) }
        #expect(descriptor.isNativeInstallable)
        #expect(installed?.key == key)
        #expect(loaded?.key == key)
        if !existed { #expect(await SourceManager.shared.source(for: key) == nil) }
    }
}
