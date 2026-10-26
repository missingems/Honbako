import Foundation

/// Shared decisions that do not require a network request or an iCloud account.
enum CloudSyncConfiguration {
    static func containerIdentifier(info: [String: Any]) -> String? {
        guard let value = info["ICLOUD_CONTAINER_ID"] as? String else { return nil }
        let identifier = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard identifier.hasPrefix("iCloud."), identifier.count > "iCloud.".count,
              !identifier.contains("$("), !identifier.contains(" ") else { return nil }
        return identifier
    }

}
