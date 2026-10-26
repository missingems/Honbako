#if SUMI
import Foundation

/// Display leaf positions grouped exactly as the reader presents them. Split
/// halves keep separate positions; their owner maps bookmarks to source pages.
struct SumiScrubberPages: Equatable {
    let groups: [[Int]]
    let total: Int

    init(total: Int, spreads: [[Int]]? = nil) {
        self.total = max(0, total)
        var seen: Set<Int> = []
        var result: [[Int]] = []
        for spread in spreads ?? [] {
            let pages = spread.filter { $0 > 0 && $0 <= total && seen.insert($0).inserted }.sorted()
            if !pages.isEmpty { result.append(pages) }
        }
        for page in 1...max(1, total) where page <= total && !seen.contains(page) { result.append([page]) }
        groups = result.sorted { ($0.first ?? 0) < ($1.first ?? 0) }
    }

    func index(containing page: Int) -> Int { groups.firstIndex { $0.contains(page) } ?? 0 }
    func label(for index: Int) -> String {
        guard groups.indices.contains(index), let first = groups[index].first, let last = groups[index].last else { return "Loading pages…" }
        return first == last ? "Page \(first) of \(total)" : "Pages \(first)–\(last) of \(total)"
    }
}
#endif
