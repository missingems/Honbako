#if SUMI
import UIKit

/// An original, bundled practice page. No third-party artwork or dialogue.
@MainActor
enum HonbakoJapanesePracticePage {
    static let phrases = ["おはよう！", "きょうもいっしょによもう。", "またあした。", "ありがとう"]

    static func render() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 1536), format: format).image { output in
            UIColor.white.setFill()
            output.fill(CGRect(x: 0, y: 0, width: 1024, height: 1536))
            UIColor.black.setStroke()
            for frame in [CGRect(x: 56, y: 56, width: 912, height: 660), CGRect(x: 56, y: 748, width: 912, height: 732)] {
                let panel = UIBezierPath(rect: frame)
                panel.lineWidth = 5
                panel.stroke()
            }
            text(phrases[0], in: CGRect(x: 118, y: 126, width: 790, height: 130), size: 98)
            text(phrases[1], in: CGRect(x: 118, y: 300, width: 790, height: 180), size: 60)
            // A simple open book is drawn using only original lines.
            let book = UIBezierPath()
            book.move(to: CGPoint(x: 512, y: 636))
            book.addLine(to: CGPoint(x: 276, y: 592))
            book.addLine(to: CGPoint(x: 276, y: 490))
            book.addLine(to: CGPoint(x: 512, y: 534))
            book.addLine(to: CGPoint(x: 748, y: 490))
            book.addLine(to: CGPoint(x: 748, y: 592))
            book.close()
            book.move(to: CGPoint(x: 512, y: 534))
            book.addLine(to: CGPoint(x: 512, y: 636))
            book.lineWidth = 5
            book.lineJoinStyle = .round
            book.stroke()
            text(phrases[2], in: CGRect(x: 118, y: 1060, width: 570, height: 130), size: 78)
            // One top-to-bottom Japanese column, read before the left bubble.
            for (index, character) in phrases[3].enumerated() {
                text(String(character), in: CGRect(x: 792, y: 828 + CGFloat(index) * 108, width: 110, height: 110), size: 92)
            }
        }
    }

    private static func text(_ string: String, in rect: CGRect, size: CGFloat) {
        (string as NSString).draw(in: rect, withAttributes: [
            .font: UIFont.systemFont(ofSize: size, weight: .medium),
            .foregroundColor: UIColor.black
        ])
    }
}
#endif
