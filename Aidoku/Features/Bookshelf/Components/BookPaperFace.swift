#if SUMI
import SwiftUI

struct BookPaperFace: View {
    var horizontalLines: Bool

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.94, green: 0.92, blue: 0.85)))
            let extent = horizontalLines ? size.height : size.width
            let count = max(3, min(32, Int(extent / 1.3)))
            for index in 1..<count {
                let position = extent * CGFloat(index) / CGFloat(count)
                var line = Path()
                if horizontalLines {
                    line.move(to: CGPoint(x: 0, y: position))
                    line.addLine(to: CGPoint(x: size.width, y: position))
                } else {
                    line.move(to: CGPoint(x: position, y: 0))
                    line.addLine(to: CGPoint(x: position, y: size.height))
                }
                context.stroke(line, with: .color(Color(red: 0.52, green: 0.46, blue: 0.34).opacity(index.isMultiple(of: 3) ? 0.3 : 0.13)), lineWidth: 0.45)
            }
        }
        .overlay {
            LinearGradient(colors: [.black.opacity(0.11), .white.opacity(0.3), .black.opacity(0.08)], startPoint: .leading, endPoint: .trailing)
        }
        .accessibilityHidden(true)
    }
}
#endif
