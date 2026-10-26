#if SUMI
import Foundation
import SwiftUI

/// A value snapshot for the shelf. Managed objects and reader state stay in
/// their existing stores; the ribbon only reflects known reading progress.
struct BookPresentation: Identifiable {
    let id: String
    var title: String
    var author: String
    var coverURL: URL?
    var backCoverURL: URL?
    var blurb: String
    var chapterLabel: String?
    var pageLabel: String?
    var progress: Double?
    var accentColor: Color

    init(
        id: String,
        title: String,
        author: String = "",
        coverURL: URL? = nil,
        backCoverURL: URL? = nil,
        blurb: String = "",
        chapterLabel: String? = nil,
        pageLabel: String? = nil,
        progress: Double? = nil,
        accentColor: Color = Color(red: 0.65, green: 0.16, blue: 0.12)
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.coverURL = coverURL
        self.backCoverURL = backCoverURL
        self.blurb = blurb
        self.chapterLabel = chapterLabel
        self.pageLabel = pageLabel
        self.progress = progress
        self.accentColor = accentColor
    }

    var normalizedProgress: Double? {
        guard let progress, progress.isFinite else { return nil }
        return min(1, max(0, progress))
    }

    var readingPositionLabel: String {
        [chapterLabel, pageLabel].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Stable placement variation, shared by shelf rendering and the tabletop.
    /// Covers never jump to a fresh angle during an ordinary data refresh.
    var placementSeed: UInt64 {
        id.utf8.reduce(UInt64(1_469_598_103_934_665_603)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }

    var restingTilt: Double { Double(placementSeed % 2_001) / 100 - 10 }
    var restingYaw: Double { 8 + Double((placementSeed >> 12) % 1_401) / 100 }
    var restingPitch: Double { -4 - Double((placementSeed >> 25) % 801) / 100 }
}
#endif
