#if SUMI
import Foundation

enum HonbakoWelcomeGate {
    static let completionKey = "Honbako.Welcome.CompletedVersion"
    static let currentVersion = 2
    static let previewArgument = "--sumi-onboarding-check"

    static func isPreview(arguments: [String]) -> Bool {
        arguments.contains(previewArgument)
    }

    static func shouldPresent(completedVersion: Int, hasPreviewBooks: Bool,
                              arguments: [String], environment: [String: String]) -> Bool {
        if isPreview(arguments: arguments) { return true }
        guard !hasPreviewBooks, completedVersion == 0,
              environment["XCTestConfigurationFilePath"] == nil,
              !arguments.contains(where: { $0.hasPrefix("--sumi-") || $0.hasPrefix("--honbako-") }) else { return false }
        return true
    }

    static func completionVersion(from previous: Int, arguments: [String]) -> Int {
        isPreview(arguments: arguments) ? previous : max(previous, currentVersion)
    }
}
#endif
