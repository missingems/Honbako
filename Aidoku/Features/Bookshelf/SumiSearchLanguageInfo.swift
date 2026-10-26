#if SUMI
import Foundation

/// Title chapter evidence takes precedence over a provider's general coverage.
struct SumiSearchLanguageInfo: Identifiable, Equatable, Sendable {
    enum Scope: Equatable, Sendable { case chapters, source }

    let scope: Scope
    let codes: [String]

    var id: String { "\(scope):\(codes.joined(separator: ","))" }

    init?(chapterLanguages: [String], translatedLanguages: [String] = [], sourceLanguages: [String]) {
        let confirmed = Self.normalized(chapterLanguages + translatedLanguages)
        if !confirmed.isEmpty {
            scope = .chapters
            codes = confirmed
        } else {
            let provider = Self.normalized(sourceLanguages)
            if !provider.isEmpty {
                scope = .source
                codes = provider
            } else if sourceLanguages.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "multi" }) {
                scope = .source
                codes = ["multi"]
            } else {
                return nil
            }
        }
    }

    var label: String { scope == .chapters ? "Chapters" : "Source Languages" }
    var names: [String] { codes.map(SourceLanguage.displayName(for:)) }
    var text: String { "\(label): \(names.joined(separator: ", "))" }
    var compactText: String {
        let visible = names.prefix(2).joined(separator: ", ")
        return "\(label): \(visible)\(names.count > 2 ? " +\(names.count - 2)" : "")"
    }
    var accessibilityText: String {
        scope == .chapters ? text : "\(text). Chapter languages have not been confirmed for this title."
    }

    private static func normalized(_ values: [String]) -> [String] {
        let codes = values.map { value in
            let code = value.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "_", with: "-").lowercased()
            return code == "es-la" ? "es-419" : code
        }.filter {
            !["und", "zxx", "mul"].contains($0)
                && $0.range(of: "^[a-z]{2,3}(-[a-z0-9]{2,8}){0,2}$", options: .regularExpression) != nil
        }
        return Array(Set(codes)).sorted {
            let result = SourceLanguage.displayName(for: $0).localizedStandardCompare(SourceLanguage.displayName(for: $1))
            return result == .orderedSame ? $0 < $1 : result == .orderedAscending
        }
    }
}
#endif
