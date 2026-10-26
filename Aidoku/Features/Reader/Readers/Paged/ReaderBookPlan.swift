import Foundation

/// Stable physical surfaces layered over the reader's canonical page identities.
/// Slots are stored in reading order; UIKit receives physical left/right order.
struct ReaderBookPlan: Equatable {
    enum Slot: Hashable {
        case page(Int)
        case wideLeft(Int)
        case wideRight(Int)
        case blank(Int)

        var canonicalIndex: Int? {
            switch self {
                case .page(let index), .wideLeft(let index), .wideRight(let index): index
                case .blank: nil
            }
        }
    }

    let groups: [[Slot]]
    var slots: [Slot] { groups.flatMap { $0 } }

    init(canonicalGroups: [[Int]], wideIndices: Set<Int> = [], leadingBlankIndices: Set<Int> = [], readingMode: ReadingMode, frontmatterIndex: Int? = nil) {
        groups = canonicalGroups.compactMap { indices in
            guard let first = indices.first else { return nil }
            if first == frontmatterIndex {
                return readingMode == .rtl ? [.page(first), .blank(first)] : [.blank(first), .page(first)]
            }
            if indices.count == 2 { return indices.map(Slot.page) }
            if wideIndices.contains(first) {
                return readingMode == .rtl ? [.wideRight(first), .wideLeft(first)] : [.wideLeft(first), .wideRight(first)]
            }
            return leadingBlankIndices.contains(first) ? [.blank(first), .page(first)] : [.page(first), .blank(first)]
        }
    }

    func physicalSlots(in group: Int, readingMode: ReadingMode) -> [Slot] {
        guard groups.indices.contains(group) else { return [] }
        return readingMode == .rtl ? groups[group].reversed() : groups[group]
    }

    func groupIndex(containing slot: Slot) -> Int? { groups.firstIndex { $0.contains(slot) } }
    func groupIndex(containingCanonicalIndex index: Int) -> Int? {
        groups.firstIndex { $0.contains { $0.canonicalIndex == index } }
    }

    func adjacentSlot(to slot: Slot, after: Bool, readingMode: ReadingMode) -> Slot? {
        let all = slots
        guard let index = all.firstIndex(of: slot) else { return nil }
        let step = (after != (readingMode == .rtl)) ? 1 : -1
        let next = index + step
        return all.indices.contains(next) ? all[next] : nil
    }
}
