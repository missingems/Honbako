#if SUMI
import UIKit

/// Original typographic guides drawn with system fonts, symbols and geometry.
@MainActor
enum HonbakoGuideRenderer {
    static func file(guide: HonbakoGuideBook, page: Int?, language: String) throws -> URL {
        let folder = FileManager.default.applicationSupportDirectory
            .appendingPathComponent("HonbakoGuides/v5/\(guide.rawValue)/\(language)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var excluded = folder; try? excluded.setResourceValues(values)
        let url = folder.appendingPathComponent(page.map { "page-\($0).png" } ?? "cover.png")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let image = render(guide: guide, page: page, language: language)
        guard let data = image.pngData() else { throw URLError(.cannotDecodeContentData) }
        try data.write(to: url, options: .atomic)
        return url
    }

    static func render(guide: HonbakoGuideBook, page: Int?, language: String) -> UIImage {
        if guide == .japanese, page == 2 { return HonbakoJapanesePracticePage.render() }
        let size = CGSize(width: 1024, height: 1536)
        let accent: UIColor = switch guide {
        case .find: UIColor(red: 0.45, green: 0.16, blue: 0.13, alpha: 1)
        case .connect: UIColor(red: 0.10, green: 0.25, blue: 0.34, alpha: 1)
        case .read: UIColor(red: 0.16, green: 0.29, blue: 0.22, alpha: 1)
        case .japanese: UIColor(red: 0.27, green: 0.21, blue: 0.37, alpha: 1)
        }
        let paper = UIColor(red: 0.97, green: 0.96, blue: 0.92, alpha: 1)
        let ink = page == nil ? paper : accent
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { output in
            (page == nil ? accent : paper).setFill()
            output.fill(CGRect(origin: .zero, size: size))
            draw("HONBAKO  /  \(String(format: "%02d", guide.number))", in: CGRect(x: 80, y: 84, width: 864, height: 64),
                font: .monospacedSystemFont(ofSize: 32, weight: .medium), color: ink)
            ink.withAlphaComponent(0.3).setFill()
            output.fill(CGRect(x: 80, y: 174, width: 864, height: 2))
            let prefix = page.map { "\(guide.prefix).\($0)" } ?? guide.prefix
            draw(HonbakoGuideLibrary.text(prefix + ".Title", language: language),
                in: CGRect(x: 80, y: 240, width: 864, height: page == nil ? 390 : 300),
                font: .systemFont(ofSize: page == nil ? 108 : 72, weight: .bold), color: ink)
            if let page {
                draw(HonbakoGuideLibrary.text(prefix + ".Body", language: language),
                    in: CGRect(x: 80, y: 570, width: 864, height: 760),
                    font: .systemFont(ofSize: 40, weight: .regular), color: UIColor.label.resolvedColor(with: .init(userInterfaceStyle: .light)))
                draw("\(page)  /  \(HonbakoGuideBook.pageCount)", in: CGRect(x: 80, y: 1400, width: 864, height: 60),
                    font: .monospacedSystemFont(ofSize: 28, weight: .regular), color: accent)
            } else {
                let symbol = UIImage(systemName: guide.symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 220, weight: .light))?
                    .withTintColor(paper, renderingMode: .alwaysOriginal)
                if let symbol {
                    let height: CGFloat = 220
                    let width = min(640, height * symbol.size.width / max(1, symbol.size.height))
                    symbol.draw(in: CGRect(x: 80, y: 760, width: width, height: height))
                }
                draw(HonbakoGuideLibrary.text(prefix + ".Subtitle", language: language),
                    in: CGRect(x: 80, y: 1160, width: 864, height: 280),
                    font: .systemFont(ofSize: 42, weight: .medium), color: paper)
            }
        }
    }

    private static func draw(_ text: String, in rect: CGRect, font: UIFont, color: UIColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 12
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }
}
#endif
