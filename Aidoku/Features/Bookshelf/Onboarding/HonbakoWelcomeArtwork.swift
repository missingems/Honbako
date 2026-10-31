#if SUMI
import SwiftUI

/// Original dune-and-ink illustrations use the onboarding accent and rounded
/// geometry, with a book or character extending beyond the device frame.
struct HonbakoWelcomeArtwork: View {
    let page: HonbakoWelcomePage
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 330, size.height / 310)
            context.translateBy(x: (size.width - 330 * scale) / 2, y: (size.height - 310 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            drawPhone(in: &context)
            if page == .library { drawLibrary(in: &context) }
            else { drawAssistant(in: &context) }
        }
    }

    private func drawPhone(in context: inout GraphicsContext) {
        let body = CGRect(x: 94, y: 18, width: 142, height: 280)
        let screen = CGRect(x: 101, y: 25, width: 128, height: 266)
        context.fill(Path(roundedRect: body.offsetBy(dx: 0, dy: 4), cornerRadius: 27), with: .color(.black.opacity(0.08)))
        context.fill(Path(roundedRect: body, cornerRadius: 27), with: .color(Color(white: 0.08)))
        context.stroke(Path(roundedRect: body.insetBy(dx: 1, dy: 1), cornerRadius: 26), with: .color(colorScheme == .dark ? .white.opacity(0.4) : Color(white: 0.35)), lineWidth: 1)
        context.fill(Path(roundedRect: screen, cornerRadius: 21), with: .color(Color(white: 0.97)))
        context.fill(Path(roundedRect: CGRect(x: 145, y: 32, width: 40, height: 11), cornerRadius: 6), with: .color(.black))
        context.fill(Path(roundedRect: CGRect(x: 143, y: 282, width: 44, height: 3), cornerRadius: 2), with: .color(.black.opacity(0.65)))
        for (y, height) in [(73.0, 20.0), (101.0, 31.0)] {
            context.fill(Path(roundedRect: CGRect(x: 91, y: y, width: 3, height: height), cornerRadius: 1.5), with: .color(Color(white: 0.22)))
        }
        context.fill(Path(roundedRect: CGRect(x: 236, y: 92, width: 3, height: 46), cornerRadius: 1.5), with: .color(Color(white: 0.22)))
    }

    private func drawLibrary(in context: inout GraphicsContext) {
        let covers = [CGRect(x: 110, y: 58, width: 49, height: 69), CGRect(x: 170, y: 58, width: 49, height: 69),
            CGRect(x: 110, y: 141, width: 49, height: 69), CGRect(x: 170, y: 141, width: 49, height: 69),
            CGRect(x: 110, y: 224, width: 49, height: 46), CGRect(x: 170, y: 224, width: 49, height: 46)]
        for (index, cover) in covers.enumerated() {
            context.fill(Path(cover), with: .color(index % 3 == 0 ? HonbakoPalette.action : .white))
            context.stroke(Path(cover), with: .color(.black), lineWidth: 1.2)
            if index % 3 == 0 {
                drawSun(in: &context, center: CGPoint(x: cover.midX, y: cover.midY), radius: 13, color: .white)
            }
            else { drawMountains(in: &context, rect: cover.insetBy(dx: 6, dy: 7)) }
        }
        var book = context
        book.translateBy(x: 37, y: 143)
        book.rotate(by: .degrees(-12))
        let cover = CGRect(x: 0, y: 0, width: 84, height: 118)
        book.fill(Path(cover.offsetBy(dx: 6, dy: 5)), with: .color(.white))
        book.stroke(Path(cover.offsetBy(dx: 6, dy: 5)), with: .color(.black), lineWidth: 1.6)
        book.fill(Path(cover), with: .color(HonbakoPalette.action))
        book.stroke(Path(cover), with: .color(.black), lineWidth: 2.2)
        let panel = cover.insetBy(dx: 15, dy: 19)
        book.fill(Path(roundedRect: panel, cornerRadius: 4), with: .color(.white))
        drawMountains(in: &book, rect: panel.insetBy(dx: 5, dy: 7))
        var spine = Path()
        spine.move(to: CGPoint(x: 8, y: 0)); spine.addLine(to: CGPoint(x: 8, y: 118))
        book.stroke(spine, with: .color(.black), lineWidth: 1)
        drawSourceCard(in: &context, rect: CGRect(x: 27, y: 65, width: 51, height: 51), symbol: "folder.fill")
        drawSourceCard(in: &context, rect: CGRect(x: 254, y: 140, width: 51, height: 51), symbol: "externaldrive.fill")
        #if HONBAKO_EXTERNAL_SOURCES
        drawSourceCard(in: &context, rect: CGRect(x: 246, y: 221, width: 51, height: 51), symbol: "puzzlepiece.extension.fill")
        #endif
    }

    private func drawAssistant(in context: inout GraphicsContext) {
        let panel = CGRect(x: 109, y: 55, width: 112, height: 164)
        context.fill(Path(panel), with: .color(.white))
        context.stroke(Path(panel), with: .color(.black), lineWidth: 1.3)
        var diagonals = Path()
        for index in 0..<8 {
            let y = 65 + Double(index) * 18
            diagonals.move(to: CGPoint(x: 111, y: y)); diagonals.addLine(to: CGPoint(x: 133, y: y + 12))
            diagonals.move(to: CGPoint(x: 218, y: y)); diagonals.addLine(to: CGPoint(x: 198, y: y + 10))
        }
        context.stroke(diagonals, with: .color(.black.opacity(0.15)), lineWidth: 1)

        // The original character steps across the frame, like an oversized panel.
        var coat = Path()
        coat.move(to: CGPoint(x: 150, y: 145))
        coat.addLine(to: CGPoint(x: 195, y: 139))
        coat.addLine(to: CGPoint(x: 252, y: 216))
        coat.addLine(to: CGPoint(x: 224, y: 257))
        coat.addLine(to: CGPoint(x: 199, y: 206))
        coat.addLine(to: CGPoint(x: 186, y: 263))
        coat.addLine(to: CGPoint(x: 113, y: 242))
        coat.addLine(to: CGPoint(x: 133, y: 185))
        coat.addLine(to: CGPoint(x: 91, y: 196))
        coat.addLine(to: CGPoint(x: 73, y: 178))
        coat.closeSubpath()
        context.fill(coat, with: .color(HonbakoPalette.action))
        context.stroke(coat, with: .color(.black), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        let face = CGRect(x: 145, y: 91, width: 52, height: 64)
        context.fill(Path(ellipseIn: face), with: .color(Color(red: 1, green: 0.94, blue: 0.84)))
        context.stroke(Path(ellipseIn: face), with: .color(.black), lineWidth: 2)
        var hair = Path()
        hair.move(to: CGPoint(x: 143, y: 123))
        for point in [CGPoint(x: 135, y: 100), CGPoint(x: 148, y: 100), CGPoint(x: 142, y: 84),
            CGPoint(x: 159, y: 91), CGPoint(x: 169, y: 75), CGPoint(x: 175, y: 89), CGPoint(x: 194, y: 83),
            CGPoint(x: 190, y: 99), CGPoint(x: 207, y: 106), CGPoint(x: 193, y: 121),
            CGPoint(x: 184, y: 107), CGPoint(x: 166, y: 112), CGPoint(x: 153, y: 108)] {
            hair.addLine(to: point)
        }
        hair.closeSubpath()
        context.fill(hair, with: .color(.black))
        var details = Path()
        details.move(to: CGPoint(x: 153, y: 126)); details.addLine(to: CGPoint(x: 161, y: 124))
        details.move(to: CGPoint(x: 178, y: 124)); details.addLine(to: CGPoint(x: 186, y: 124))
        details.move(to: CGPoint(x: 164, y: 140)); details.addQuadCurve(to: CGPoint(x: 181, y: 139), control: CGPoint(x: 174, y: 148))
        details.move(to: CGPoint(x: 157, y: 162)); details.addLine(to: CGPoint(x: 171, y: 183))
        details.addLine(to: CGPoint(x: 187, y: 157))
        details.move(to: CGPoint(x: 167, y: 186)); details.addLine(to: CGPoint(x: 153, y: 232))
        context.stroke(details, with: .color(.black), style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))

        drawBubble(in: &context, rect: CGRect(x: 193, y: 48, width: 122, height: 42), text: "Who is this?", tail: CGPoint(x: 211, y: 109))
        let note = CGRect(x: 15, y: 223, width: 110, height: 53)
        context.fill(Path(roundedRect: note, cornerRadius: 11), with: .color(Color(red: 0.95, green: 0.91, blue: 0.83)))
        context.stroke(Path(roundedRect: note, cornerRadius: 11), with: .color(.black), lineWidth: 1.4)
        context.draw(Text("ここから").font(.system(size: 17, weight: .semibold)).foregroundStyle(.black), at: CGPoint(x: note.midX, y: note.minY + 18))
        context.draw(Text("ko · ko · ka · ra").font(.system(size: 10, weight: .medium)).foregroundStyle(.black.opacity(0.7)), at: CGPoint(x: note.midX, y: note.minY + 38))
    }

    private func drawMountains(in context: inout GraphicsContext, rect: CGRect) {
        var mountains = Path()
        mountains.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        mountains.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.2))
        mountains.addLine(to: CGPoint(x: rect.midX + rect.width * 0.12, y: rect.midY))
        mountains.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY + rect.height * 0.38))
        mountains.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        mountains.closeSubpath()
        context.fill(mountains, with: .color(.black.opacity(0.85)))
        var hatch = Path()
        for index in 0..<5 {
            let x = rect.minX + rect.width * 0.2 + Double(index) * rect.width * 0.085
            hatch.move(to: CGPoint(x: x, y: rect.maxY - 4))
            hatch.addLine(to: CGPoint(x: x + 9, y: rect.maxY - 20))
        }
        context.stroke(hatch, with: .color(.white.opacity(0.65)), lineWidth: 0.8)
    }

    private func drawSun(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat, color: Color = .black) {
        context.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(color), lineWidth: 1.5)
        var horizon = Path()
        horizon.move(to: .init(x: center.x - 19, y: center.y + 9))
        horizon.addLine(to: .init(x: center.x + 19, y: center.y + 9))
        context.stroke(horizon, with: .color(color), lineWidth: 1.1)
    }

    private func drawSourceCard(in context: inout GraphicsContext, rect: CGRect, symbol: String) {
        let card = Path(roundedRect: rect, cornerRadius: 13)
        context.fill(card, with: .color(.white))
        context.stroke(card, with: .color(HonbakoPalette.action.opacity(0.35)), lineWidth: 1.2)
        var icon = context.resolve(Image(systemName: symbol))
        icon.shading = .color(HonbakoPalette.action)
        context.draw(icon, in: rect.insetBy(dx: 12, dy: 12))
    }

    private func drawBubble(in context: inout GraphicsContext, rect: CGRect, text: String, tail: CGPoint) {
        var tailPath = Path()
        tailPath.move(to: .init(x: rect.minX + 18, y: rect.maxY - 2))
        tailPath.addLine(to: tail)
        tailPath.addLine(to: .init(x: rect.minX + 34, y: rect.maxY - 2))
        tailPath.closeSubpath()
        context.fill(tailPath, with: .color(.white))
        context.stroke(tailPath, with: .color(.black), lineWidth: 1.5)
        context.fill(Path(roundedRect: rect, cornerRadius: 15), with: .color(.white))
        context.stroke(Path(roundedRect: rect, cornerRadius: 15), with: .color(.black), lineWidth: 1.5)
        context.draw(Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(.black), at: .init(x: rect.midX, y: rect.midY))
    }
}
#endif
