#if SUMI
import UIKit

/// Upright Latin readings form a narrow companion column for vertical text.
/// Horizontal text retains a single reading row above or below its real anchor.
@MainActor
enum HonbakoJapaneseAnnotationStyle {
    static func labelSize(
        for romaji: String,
        font: UIFont,
        direction: HonbakoJapaneseRegion.Direction,
        wordBox: CGRect
    ) -> CGSize {
        let measured = (romaji as NSString).size(withAttributes: [.font: font])
        guard direction == .vertical else {
            return CGSize(width: ceil(measured.width) + 8, height: max(20, ceil(font.lineHeight) + 6))
        }
        // A long reading wraps upright alongside its word instead of stretching
        // over the next text column. The word's measured height controls density.
        let width = ceil(min(measured.width, max(font.pointSize * 3, min(font.pointSize * 5, wordBox.height))))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byCharWrapping
        let rect = (romaji as NSString).boundingRect(
            with: CGSize(width: max(1, width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: paragraph], context: nil)
        return CGSize(width: width + 8, height: max(20, ceil(rect.height) + 6))
    }
}
#endif
