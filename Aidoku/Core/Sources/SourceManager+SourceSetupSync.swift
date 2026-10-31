#if SUMI
import AidokuRunner
import Foundation

extension SourceManager {
    private nonisolated static func provenanceKey(_ id: String) -> String { "Honbako.SourceSetup.Provenance." + id }

    func rememberSourceProvenance(_ value: HonbakoSourceSetupRecord) {
        var record = value
        if record.packageSHA256 == nil,
           let data = UserDefaults.standard.data(forKey: Self.provenanceKey(record.id)),
           let previous = try? JSONDecoder().decode(HonbakoSourceSetupRecord.self, from: data),
           previous.version == record.version, previous.packageURL == record.packageURL {
            record.packageSHA256 = previous.packageSHA256
        }
        guard record.kind == .extensionPackage, let data = HonbakoSourceSetupPolicy.encode(record) else { return }
        UserDefaults.standard.set(data, forKey: Self.provenanceKey(record.id))
        NotificationCenter.default.post(name: .init("Honbako.SourceSetup.Changed"), object: nil)
    }

    /// Uses only explicit Source fields and our own safe provenance records, never source preferences.
    func sourceSetupRecords() async -> [HonbakoSourceSetupRecord] {
        let objects = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getSources(context: context).map { $0.toData() }
        }
        let infos = await getSourceInfos(sorted: false)
        let byID = Dictionary(infos.map { ($0.sourceId, $0) }, uniquingKeysWith: { first, _ in first })
        var records: [HonbakoSourceSetupRecord] = []
        for object in objects {
            let info = byID[object.id]
            var record: HonbakoSourceSetupRecord?
            if let data = object.customSource, let config = try? CustomSourceConfig(from: data) {
                switch config {
                case .demo: break
                case .local:
                    record = .init(id: object.id, kind: .local, name: info?.name ?? "On This Device")
                case .honbakoMangaDex:
                    record = .init(id: object.id, kind: .mangaDex, name: info?.name ?? "MangaDex", version: info?.version)
                case .komga(let value), .kavita(let value), .suwayomi(let value):
                    let kind: HonbakoSourceSetupRecord.Kind = switch config {
                    case .komga: .komga
                    case .kavita: .kavita
                    default: .suwayomi
                    }
                    guard value.key == object.id else { continue }
                    record = .init(id: value.key, kind: kind, name: value.name, serverURL: value.server)
                }
            } else {
                if let data = UserDefaults.standard.data(forKey: Self.provenanceKey(object.id)),
                   let saved = HonbakoSourceSetupPolicy.decode(data, key: HonbakoSourceSetupPolicy.key(for: .init(id: object.id, kind: .extensionPackage, name: object.id))),
                   saved.id == object.id, saved.version == info?.version || info == nil {
                    record = saved
                } else {
                    // An ID or matching catalog entry does not establish the package's install provenance.
                    record = .init(id: object.id, kind: .extensionPackage, name: info?.name ?? object.id, version: info?.version)
                }
            }
            if var record {
                record.disabled = info?.disabled ?? false
                record.removed = false
                if HonbakoSourceSetupPolicy.validate(record) { records.append(record) }
            }
        }
        for url in getSourceListURLs() {
            let record = HonbakoSourceSetupRecord(id: url.absoluteString, kind: .repository,
                name: url.host ?? "Extension repository", repositoryURL: url.absoluteString)
            if HonbakoSourceSetupPolicy.validate(record) { records.append(record) }
        }
        return records
    }

    /// Rebuilds only bundled implementations. Local configuration and authentication always win.
    func restoreSourceSetupConnections(_ records: [HonbakoSourceSetupRecord]) async {
        var restored: [HonbakoSourceSetupRecord] = []
        for record in records where !record.removed && HonbakoSourceSetupPolicy.validate(record) {
            if record.kind == .repository {
                if let url = record.repositoryURL.flatMap({ HonbakoSourceSetupPolicy.safeURL($0) }) {
                    restoreSourceListReference(url: url)
                }
                continue
            }
            guard let config = sourceSetupConfig(record) else { continue }
            let source = config.toSource()
            let inserted = await CoreDataManager.shared.container.performBackgroundTask { context in
                guard !CoreDataManager.shared.hasSource(key: record.id, context: context) else { return false }
                let object = CoreDataManager.shared.createSource(source: source, context: context)
                object.customSource = config.encode() as NSObject
                do { try context.save(); return true } catch { return false }
            }
            if inserted {
                // No login state is transferred; the server runner will request local authentication.
                if let server = record.serverURL, UserDefaults.standard.object(forKey: "\(record.id).server") == nil {
                    UserDefaults.standard.set(server, forKey: "\(record.id).server")
                }
                restored.append(record)
            }
        }
        guard !restored.isEmpty else { return }
        await reloadSources()
        for record in restored where record.disabled { await disable(sourceKey: record.id) }
    }

    private func sourceSetupConfig(_ record: HonbakoSourceSetupRecord) -> CustomSourceConfig? {
        switch record.kind {
        case .local: return .local
        #if HONBAKO_EXTERNAL_SOURCES
        case .mangaDex: return .honbakoMangaDex
        #else
        case .mangaDex: return nil
        #endif
        case .komga, .kavita, .suwayomi:
            guard let server = record.serverURL else { return nil }
            let value = CustomSourceConfig.KeyNameServer(key: record.id, name: record.name, server: server)
            return switch record.kind {
            case .komga: .komga(value)
            case .kavita: .kavita(value)
            default: .suwayomi(value)
            }
        case .extensionPackage, .repository: return nil
        }
    }

    /// Called only from the visible Restore confirmation, never by background iCloud changes.
    func restoreSourceSetupPackage(_ record: HonbakoSourceSetupRecord) async -> Bool {
        #if HONBAKO_EXTERNAL_SOURCES
        guard HonbakoSourceSetupPolicy.validate(record), !record.removed, record.kind == .extensionPackage,
              let version = record.version, let text = record.packageURL,
              let url = HonbakoSourceSetupPolicy.safeURL(text) else { return false }
        if await getSourceInfos().contains(where: { $0.sourceId == record.id }) { return true }
        // Older records without byte integrity need their original repository to still advertise
        // the exact approved version and package location. Never choose a newer catalog version.
        if record.packageSHA256 == nil {
            guard let repository = record.repositoryURL.flatMap({ HonbakoSourceSetupPolicy.safeURL($0) }),
                  let list = await loadSourceListForSetupRestore(url: repository),
                  list.sources.contains(where: { $0.id == record.id && $0.version == version && $0.fileURL?.absoluteURL == url }) else { return false }
        }
        guard let source = await importSource(from: url, expectedSourceID: record.id,
            expectedVersion: version, expectedSHA256: record.packageSHA256), source.key == record.id else { return false }
        rememberSourceProvenance(record)
        if record.disabled { await disable(sourceKey: record.id) }
        return true
        #else
        return false
        #endif
    }

    func sourceSetupSettingsSource(id: String) async -> AidokuRunner.Source? {
        let object = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getSource(key: id, context: context)?.toData()
        }
        return await object?.toNewSource()
    }

    func sourceSetupMissingLibraryIDs() async -> [String] {
        let installed = Set(await getSourceInfos().map(\.sourceId))
        let library = await CoreDataManager.shared.container.performBackgroundTask { context in
            Set(CoreDataManager.shared.getLibraryManga(context: context).compactMap { $0.manga?.sourceId })
        }
        return library.subtracting(installed).filter {
            $0 != HonbakoTutorialManga.sourceKey && HonbakoSourceSetupPolicy.sourceID($0)
        }.sorted()
    }
}
#endif
