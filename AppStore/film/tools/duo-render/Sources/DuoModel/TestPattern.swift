import CoreGraphics
import CoreText
import Foundation

/// Framebuffer-sized test patterns in each panel's native, unrotated orientation, row 0 at the
/// top, as CoreSimulator delivers LCD (1398×2034) and LCD-1 (2007×2853).
///
/// They stand in for the stream until the client has one, and they show whether a frame lands on
/// the model the right way round. Every pattern has four tinted quadrants (TL red, TR green, BL
/// blue, BR amber), corner blocks labelled with their pixel coordinates, a grid (50 px faint,
/// 100 px light, 500 px bright, labelled every 200 px along the top and left edges), a centre
/// cross, and the panel's mask corner radii as cyan arcs. The cover adds the camera disc (111 px
/// at (1254, 143)). The inner panel adds the fold row, y = 1426.5, as a red line, SpringBoard's
/// 40-pt fold region (rows 1366.5–1486.5) as a light band, and the model's crease band.
///
/// CoreGraphics and CoreText only, so it draws on visionOS too.
public enum TestPattern {
  public static func image(for display: DuoModel.Display) -> CGImage {
    let size = display.framebufferSize
    let w = size.x
    let h = size.y
    let ctx = CGContext(
      data: nil,
      width: w,
      height: h,
      bitsPerComponent: 8,
      bytesPerRow: w * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    // Row 0 at the top: flip so y grows downwards, as framebuffer rows do.
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: 1, y: -1)
    let width = CGFloat(w)
    let height = CGFloat(h)
    let cx = width / 2
    let cy = height / 2

    // Quadrants.
    let tints: [(CGFloat, CGFloat, CGFloat)] = [
      (0.42, 0.10, 0.10), (0.08, 0.34, 0.12), (0.10, 0.14, 0.44), (0.42, 0.33, 0.05),
    ]
    for (i, tint) in tints.enumerated() {
      ctx.setFillColor(CGColor(srgbRed: tint.0, green: tint.1, blue: tint.2, alpha: 1))
      ctx.fill(CGRect(x: i % 2 == 0 ? 0 : cx, y: i < 2 ? 0 : cy, width: cx, height: cy))
    }

    // Inner: SpringBoard's 40-pt fold region around the fold row.
    if display == .inner {
      ctx.setFillColor(CGColor(gray: 1, alpha: 0.16))
      ctx.fill(CGRect(x: 0, y: 1426.5 - 60, width: width, height: 120))
    }

    // Grid.
    func lines(step: Int, lineWidth: CGFloat, alpha: CGFloat) {
      ctx.setStrokeColor(CGColor(gray: 1, alpha: alpha))
      ctx.setLineWidth(lineWidth)
      for x in stride(from: 0, through: w, by: step) {
        ctx.move(to: CGPoint(x: CGFloat(x), y: 0))
        ctx.addLine(to: CGPoint(x: CGFloat(x), y: height))
      }
      for y in stride(from: 0, through: h, by: step) {
        ctx.move(to: CGPoint(x: 0, y: CGFloat(y)))
        ctx.addLine(to: CGPoint(x: width, y: CGFloat(y)))
      }
      ctx.strokePath()
    }
    lines(step: 50, lineWidth: 1, alpha: 0.18)
    lines(step: 100, lineWidth: 2, alpha: 0.35)
    lines(step: 500, lineWidth: 5, alpha: 0.85)
    for x in stride(from: 200, to: w - 100, by: 200) {
      text(ctx, "\(x)", CGFloat(x) + 6, 96, size: 30, color: CGColor(gray: 1, alpha: 0.9))
    }
    for y in stride(from: 200, to: h - 100, by: 200) {
      text(ctx, "\(y)", 100, CGFloat(y) + 6, size: 30, color: CGColor(gray: 1, alpha: 0.9))
    }

    // Mask corner radii, from the mask PDFs: the cover's are 24 px on the x = 0 edge and 177 px
    // on the other; the inner panel's are all 160.3 px.
    let radii: [CGFloat] = display == .cover ? [24, 177, 24, 177] : [160.3, 160.3, 160.3, 160.3]
    ctx.setStrokeColor(CGColor(srgbRed: 0, green: 1, blue: 1, alpha: 1))
    ctx.setLineWidth(5)
    let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
      (0, 0, 1, 1), (width, 0, -1, 1), (0, height, 1, -1), (width, height, -1, -1),
    ]
    for (i, corner) in corners.enumerated() {
      let r = radii[i]
      let centre = CGPoint(x: corner.0 + corner.2 * r, y: corner.1 + corner.3 * r)
      ctx.addArc(center: centre, radius: r, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
      ctx.strokePath()
    }

    // Corner blocks with their pixel coordinates.
    let blockColors: [CGColor] = [
      CGColor(srgbRed: 1, green: 0.2, blue: 0.2, alpha: 1),
      CGColor(srgbRed: 0.2, green: 1, blue: 0.3, alpha: 1),
      CGColor(srgbRed: 0.3, green: 0.5, blue: 1, alpha: 1),
      CGColor(srgbRed: 1, green: 0.85, blue: 0.1, alpha: 1),
    ]
    let names = ["TL (0,0)", "TR (\(w - 1),0)", "BL (0,\(h - 1))", "BR (\(w - 1),\(h - 1))"]
    let block: CGFloat = 200
    let inset: CGFloat = display == .cover ? 60 : 110
    for i in 0..<4 {
      let x = i % 2 == 0 ? inset : width - inset - block
      // On the cover the TR block sits below the camera disc, so the disc stays clear.
      let y = i < 2 ? inset + (display == .cover && i == 1 ? 260 : 60) : height - inset - block - 60
      ctx.setFillColor(blockColors[i])
      ctx.fill(CGRect(x: x, y: y, width: block, height: block))
      let label = names[i]
      let labelWidth = CGFloat(label.count) * 30
      text(
        ctx, label, i % 2 == 0 ? x : x + block - labelWidth, i < 2 ? y + block + 8 : y - 64,
        size: 52, color: CGColor(gray: 1, alpha: 1)
      )
      text(ctx, ["TL", "TR", "BL", "BR"][i], x + 30, y + 50, size: 100, color: CGColor(gray: 0, alpha: 1))
    }

    // Centre cross.
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0.2, blue: 1, alpha: 1))
    ctx.setLineWidth(8)
    ctx.move(to: CGPoint(x: cx - 220, y: cy))
    ctx.addLine(to: CGPoint(x: cx + 220, y: cy))
    ctx.move(to: CGPoint(x: cx, y: cy - 220))
    ctx.addLine(to: CGPoint(x: cx, y: cy + 220))
    ctx.strokePath()
    text(
      ctx, String(format: "centre (%.1f, %.1f)", Double(cx), Double(cy)), cx + 24, cy + 20,
      size: 40, color: CGColor(gray: 1, alpha: 1)
    )

    // Titles and direction arrows. On the cover the title sits below the moved TR block and its
    // label (y 320–580).
    let title = display == .cover ? "COVER  LCD  1398x2034" : "INNER  LCD-1  2007x2853"
    text(
      ctx, title, display == .cover ? 170 : 300, display == .cover ? 640 : 420,
      size: display == .cover ? 90 : 110, color: CGColor(gray: 1, alpha: 1)
    )
    text(
      ctx, "native, row 0 at the top", display == .cover ? 170 : 300, display == .cover ? 760 : 540,
      size: 64, color: CGColor(gray: 1, alpha: 0.95)
    )
    arrow(ctx, from: CGPoint(x: cx - 350, y: 300), to: CGPoint(x: cx + 250, y: 300), label: "+x", width: 10)
    arrow(ctx, from: CGPoint(x: 300, y: cy - 700), to: CGPoint(x: 300, y: cy - 150), label: "+y", width: 10)

    if display == .cover {
      // The framebuffer's camera disc: 111 px across, centred at (1254, 143), black as the
      // simulator draws it, with a white rim and a cyan ring 80 px out, both concentric with it.
      ctx.setFillColor(CGColor(gray: 0, alpha: 1))
      ctx.fillEllipse(in: CGRect(x: 1254 - 55.5, y: 143 - 55.5, width: 111, height: 111))
      ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
      ctx.setLineWidth(3)
      ctx.strokeEllipse(in: CGRect(x: 1254 - 55.5, y: 143 - 55.5, width: 111, height: 111))
      ctx.setStrokeColor(CGColor(srgbRed: 0, green: 1, blue: 1, alpha: 1))
      ctx.setLineWidth(4)
      ctx.strokeEllipse(in: CGRect(x: 1254 - 80, y: 143 - 80, width: 160, height: 160))
      ctx.move(to: CGPoint(x: 1254 - 100, y: 143))
      ctx.addLine(to: CGPoint(x: 1254 - 60, y: 143))
      ctx.move(to: CGPoint(x: 1254 + 60, y: 143))
      ctx.addLine(to: CGPoint(x: 1254 + 100, y: 143))
      ctx.move(to: CGPoint(x: 1254, y: 143 + 60))
      ctx.addLine(to: CGPoint(x: 1254, y: 143 + 100))
      ctx.strokePath()
      text(ctx, "camera disc (1254,143)", 700, 232, size: 36, color: CGColor(gray: 1, alpha: 1))
      text(ctx, "hinge side: x = 0 edge", 60, cy + 300, size: 56, color: CGColor(gray: 1, alpha: 1))
    } else {
      // The model's crease band (|x| < 7.28 mm, rows 1295–1558), where the skinned mesh bends.
      ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0.6, blue: 0.1, alpha: 1))
      ctx.setLineWidth(4)
      ctx.setLineDash(phase: 0, lengths: [30, 20])
      for y in [1426.5 - 131.5, 1426.5 + 131.5] {
        ctx.move(to: CGPoint(x: 0, y: y))
        ctx.addLine(to: CGPoint(x: width, y: y))
      }
      ctx.strokePath()
      ctx.setLineDash(phase: 0, lengths: [])
      text(
        ctx, "model crease band, rows 1295-1558", 1100, 1426.5 + 140,
        size: 36, color: CGColor(srgbRed: 1, green: 0.7, blue: 0.3, alpha: 1)
      )
      // The fold row.
      ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0.05, blue: 0.05, alpha: 1))
      ctx.setLineWidth(10)
      ctx.move(to: CGPoint(x: 0, y: 1426.5))
      ctx.addLine(to: CGPoint(x: width, y: 1426.5))
      ctx.strokePath()
      text(
        ctx, "FOLD  y = 1426.5", 1300, 1426.5 - 110,
        size: 56, color: CGColor(srgbRed: 1, green: 0.4, blue: 0.4, alpha: 1)
      )
      text(ctx, "native top half, rows 0-1426", 330, 900, size: 80, color: CGColor(gray: 1, alpha: 1))
      text(ctx, "native bottom half, rows 1427-2852", 250, 1900, size: 80, color: CGColor(gray: 1, alpha: 1))
    }
    return ctx.makeImage()!
  }

  /// Draws upright text with its top-left corner at (x, y) in the flipped, row-down context.
  static func text(_ ctx: CGContext, _ string: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, color: CGColor) {
    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    let attributes = [
      NSAttributedString.Key(kCTFontAttributeName as String): font,
      NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
    ] as [NSAttributedString.Key: Any]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    ctx.saveGState()
    ctx.translateBy(x: x, y: y + size)
    ctx.scaleBy(x: 1, y: -1)
    ctx.textPosition = .zero
    CTLineDraw(line, ctx)
    ctx.restoreGState()
  }

  static func arrow(_ ctx: CGContext, from a: CGPoint, to b: CGPoint, label: String, width: CGFloat) {
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.setLineWidth(width)
    ctx.move(to: a)
    ctx.addLine(to: b)
    ctx.strokePath()
    let d = CGPoint(x: b.x - a.x, y: b.y - a.y)
    let length = (d.x * d.x + d.y * d.y).squareRoot()
    let u = CGPoint(x: d.x / length, y: d.y / length)
    let n = CGPoint(x: -u.y, y: u.x)
    ctx.move(to: CGPoint(x: b.x + u.x * 40, y: b.y + u.y * 40))
    ctx.addLine(to: CGPoint(x: b.x + n.x * 30, y: b.y + n.y * 30))
    ctx.addLine(to: CGPoint(x: b.x - n.x * 30, y: b.y - n.y * 30))
    ctx.closePath()
    ctx.fillPath()
    text(
      ctx, label, b.x + u.x * 60 + (u.x == 0 ? 20 : 0), b.y + u.y * 60 - (u.y == 0 ? 30 : 0),
      size: 60, color: CGColor(gray: 1, alpha: 1)
    )
  }
}
