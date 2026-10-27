#if SUMI
import Foundation

struct SumiSearchSourceSection: Identifiable {
    let sourceKey: String
    let name: String
    let books: [SumiBook]

    var id: String { sourceKey }

    /// Preserve the first visible source and row order as other sources finish.
    /// The same title from another provider remains in that provider's section.
    static func grouping(_ books: [SumiBook], sourceName: (String) -> String) -> [Self] {
        var keys: [String] = []
        var grouped: [String: [SumiBook]] = [:]
        for book in books {
            if grouped[book.sourceKey] == nil { keys.append(book.sourceKey) }
            grouped[book.sourceKey, default: []].append(book)
        }
        return keys.map { Self(sourceKey: $0, name: sourceName($0), books: grouped[$0] ?? []) }
    }
}
#endif
