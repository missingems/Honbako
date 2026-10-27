#if SUMI
import Foundation

enum SumiSearchSourcePreferences {
    static func fingerprint(sourceKey: String) -> Int {
        let values = UserDefaults.standard.dictionaryRepresentation().filter { $0.key.hasPrefix(sourceKey + ".") }
        // Retain property-list types so a language/filter change invalidates
        // both raw provider pages and their prepared row snapshots.
        let ordered: [[Any]] = values.sorted { $0.key < $1.key }.map { [$0.key, $0.value] }
        return (try? PropertyListSerialization.data(fromPropertyList: ordered, format: .binary, options: 0))?.hashValue ?? 0
    }
}
#endif
