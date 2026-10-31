import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
import AppKit

// Original dune-and-ink manga cover with the native Japanese title 本箱.
// Keep the book centered while changing its tilt and Home Screen scale.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let design = root.appendingPathComponent("Design/AppIcon")
let assets = root.appendingPathComponent("Aidoku/App/Resources/Assets.xcassets/SumiIcon.appiconset")
try FileManager.default.createDirectory(at: design, withIntermediateDirectories: true)

let variants: [(name: String, file: String, background: String, cover: String, paper: String, ink: String)] = [
    ("light", "SumiIcon.png", "#F5F0E6", "#806344", "#FFFCF5", "#211E19"),
    ("dark", "SumiIcon-dark.png", "#171410", "#CBAA80", "#F5EBD9", "#211E19"),
    ("tinted", "SumiIcon-tinted.png", "#171717", "#BDBDBD", "#F7F7F7", "#202020")
]

/// Shape the Japanese title with Core Text, then bake
/// the outlines into the SVG so exported icon assets have no font dependency.
func outlinedCoverTitle(_ text: String) -> String {
    let face = CTFontCreateWithName("HiraginoSans-W8" as CFString, 210, nil)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): face,
        NSAttributedString.Key(kCTKernAttributeName as String): 0.0
    ]))
    let combined = CGMutablePath()
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
        for (glyph, position) in zip(glyphs, positions) {
            guard let outline = CTFontCreatePathForGlyph(face, glyph, nil) else { continue }
            combined.addPath(outline, transform: CGAffineTransform(translationX: position.x, y: position.y))
        }
    }
    var path = ""
    combined.applyWithBlock { element in
        let e = element.pointee
        func xy(_ point: CGPoint) -> String { "\(point.x) \(point.y)" }
        switch e.type {
        case .moveToPoint: path += "M" + xy(e.points[0])
        case .addLineToPoint: path += "L" + xy(e.points[0])
        case .addQuadCurveToPoint: path += "Q" + xy(e.points[0]) + " " + xy(e.points[1])
        case .addCurveToPoint: path += "C" + xy(e.points[0]) + " " + xy(e.points[1]) + " " + xy(e.points[2])
        case .closeSubpath: path += "Z"
        @unknown default: break
        }
    }
    return path
}

// Traditional top-to-bottom manga-cover lettering. Optical centering uses
// the actual glyph outlines, leaving equal paper margins above and below.
let titlePaths = ["本", "箱"].map(outlinedCoverTitle)

for variant in variants {
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
      <defs><filter id="shadow" x="-30%" y="-20%" width="160%" height="150%"><feDropShadow dx="0" dy="16" stdDeviation="13" flood-color="#100D08" flood-opacity="0.16"/></filter></defs>
      <rect width="1024" height="1024" fill="\(variant.background)"/>
      <g transform="translate(512 512) scale(1.06) rotate(5) translate(-512 -512)" stroke="\(variant.ink)" stroke-linecap="round" stroke-linejoin="round">
        <g filter="url(#shadow)">
          <rect x="258" y="188" width="484" height="676" rx="8" fill="\(variant.paper)" stroke-width="10"/>
          <path d="M276 835 H726 M276 847 H724" fill="none" stroke-width="3" opacity="0.45"/>
          <rect x="280" y="164" width="484" height="676" rx="8" fill="\(variant.cover)" stroke-width="12"/>
        </g>
        <path d="M716 174 V830" stroke-width="6" fill="none"/>
        <path d="M303 207 H687 V673 H303 Z" fill="\(variant.paper)" stroke="none"/>
        <g id="cover-title" aria-label="本箱" fill="\(variant.ink)" stroke="none">
          <path transform="translate(390 407) scale(1 -1)" d="\(titlePaths[0])"/>
          <path transform="translate(393 632) scale(1 -1)" d="\(titlePaths[1])"/>
        </g>
        <path d="M308 716 H511 M308 745 H452" fill="none" stroke="\(variant.paper)" stroke-width="11"/>
        <rect x="595" y="711" width="86" height="69" fill="\(variant.ink)" stroke="none"/>
        <path d="M615 731 H660 M615 747 H654 M615 763 H660" fill="none" stroke="\(variant.paper)" stroke-width="3"/>
      </g>
    </svg>
    """
    let vector = design.appendingPathComponent("HonbakoIcon-\(variant.name).svg")
    try svg.write(to: vector, atomically: true, encoding: .utf8)
    let intermediate = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
    defer { try? FileManager.default.removeItem(at: intermediate) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/rsvg-convert")
    process.arguments = ["--width", "1024", "--height", "1024", "--output", intermediate.path, vector.path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0,
          let source = CGImageSourceCreateWithURL(intermediate as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                                  bytesPerRow: 4096, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        fatalError("Could not render icon")
    }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    context.draw(image, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    let output = assets.appendingPathComponent(variant.file)
    guard let flattened = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Could not write icon")
    }
    CGImageDestinationAddImage(destination, flattened, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not finalize icon") }
    print("Rendered \(variant.file): 1024 × 1024, opaque sRGB")
}

let contents: [String: Any] = [
    "images": [
        ["filename": "SumiIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"],
        ["filename": "SumiIcon-dark.png", "idiom": "universal", "platform": "ios", "size": "1024x1024",
         "appearances": [["appearance": "luminosity", "value": "dark"]]],
        ["filename": "SumiIcon-tinted.png", "idiom": "universal", "platform": "ios", "size": "1024x1024",
         "appearances": [["appearance": "luminosity", "value": "tinted"]]]
    ],
    "info": ["author": "xcode", "version": 1]
]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: assets.appendingPathComponent("Contents.json"), options: .atomic)
