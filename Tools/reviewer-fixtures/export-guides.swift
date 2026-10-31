// Native fixture export: compiles the existing renderer unchanged.
import Foundation
import UIKit

@MainActor
enum HonbakoGuideLibrary {
    private static let strings: [String: String] = {
        let url = URL(fileURLWithPath: CommandLine.arguments[2])
            .appendingPathComponent("Aidoku/App/Resources/Localization/en.lproj/Localizable.strings")
        return (try? PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)) as? [String: String] ?? [:]
    }()
    static func text(_ key: String, language: String) -> String { strings[key] ?? key }
}

extension FileManager {
    var applicationSupportDirectory: URL { URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true) }
}

@main
@MainActor
struct ExportGuides {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        for guide in HonbakoGuideBook.allCases {
            let directory = root.appendingPathComponent(guide.rawValue, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for page in [Int?](arrayLiteral: nil) + (1...HonbakoGuideBook.pageCount).map(Optional.some) {
                let image = HonbakoGuideRenderer.render(guide: guide, page: page, language: "en")
                guard let data = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
                try data.write(to: directory.appendingPathComponent(page.map { "page-\($0).png" } ?? "cover.png"))
            }
            print("Exported \(guide.rawValue): original cover and \(HonbakoGuideBook.pageCount) pages")
        }
    }
}
