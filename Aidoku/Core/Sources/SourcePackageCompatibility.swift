import Foundation

/// Source manifests describe the reader engine API, independently of the
/// product's public version (Honbako 0.1 can embed the 0.9 reader engine).
enum SourcePackageCompatibility {
    static var versionString: String {
        configuredVersion(in: Bundle.main.infoDictionary ?? [:])
    }

    static func configuredVersion(in metadata: [String: Any]) -> String {
        metadata["SourceEngineVersion"] as? String
            ?? metadata["CFBundleShortVersionString"] as? String
            ?? "0"
    }

    static func supports(minimum: String?, maximum: String?, version: String = versionString) -> Bool {
        let version = SemanticVersion(version)
        if let minimum, SemanticVersion(minimum) > version { return false }
        if let maximum, SemanticVersion(maximum) < version { return false }
        return true
    }
}
