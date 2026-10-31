#if SUMI
import Foundation

struct HonbakoSourceSetupRecovery: Identifiable, Equatable {
    let id: String
    let record: HonbakoSourceSetupRecord?
    var name: String { record?.name ?? (id == "honbako.mangadex" ? "MangaDex" : id) }
    var canReconnectBundledSource: Bool {
        #if HONBAKO_EXTERNAL_SOURCES
        id == "honbako.mangadex"
        #else
        false
        #endif
    }
    var canRestorePackage: Bool {
        guard let record, record.kind == .extensionPackage, record.version != nil,
              record.packageURL != nil, !record.removed else { return false }
        return record.packageSHA256 != nil || record.repositoryURL != nil
    }
}
#endif
