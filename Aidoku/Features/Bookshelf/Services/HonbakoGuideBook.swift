#if SUMI
import Foundation

enum HonbakoGuideBook: String, CaseIterable, Sendable {
    case find = "guide-find"
    case connect = "guide-connect"
    case read = "guide-read"
    case japanese = "guide-japanese"

    var prefix: String { "Honbako.Guide.\(rawValue)" }
    var symbol: String {
        switch self {
        case .find: "magnifyingglass"
        case .connect: "externaldrive.connected.to.line.below"
        case .read: "book.pages"
        case .japanese: "character.book.closed"
        }
    }
    var number: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }
    var seedKey: String { "Honbako.Guide.Installed.\(rawValue).v1" }
    static let pageCount = 4

    static func shouldInstall(previouslyInstalled: Bool, isInLibrary: Bool) -> Bool {
        !previouslyInstalled && !isInLibrary
    }
}
#endif
