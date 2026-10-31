#if SUMI
import Foundation
import Security

enum HonbakoAutomationCredentials {
    private static var service: String { (Bundle.main.bundleIdentifier ?? "Honbako") + ".automation" }
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "paired-device"]
    }
    static func load() -> HonbakoAutomationModels.Connection? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(HonbakoAutomationModels.Connection.self, from: data)
    }
    static func save(_ connection: HonbakoAutomationModels.Connection) throws {
        let data = try JSONEncoder().encode(connection)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            for (key, value) in attributes { item[key] = value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw Failure.unavailable }
        } else if status != errSecSuccess { throw Failure.unavailable }
    }
    static func remoteIdentity(endpoint: URL = HonbakoRemoteMCP.endpoint) throws -> HonbakoRemoteMCPIdentity {
        guard let account = HonbakoRemoteMCP.identityAccount(for: endpoint) else { throw Failure.unavailable }
        var item = query
        item[kSecAttrAccount as String] = account
        var lookup = item
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecSuccess {
            guard let data = result as? Data,
                  let identity = try? JSONDecoder().decode(HonbakoRemoteMCPIdentity.self, from: data) else {
                throw Failure.unavailable
            }
            return identity
        }
        guard status == errSecItemNotFound else { throw Failure.unavailable }
        let identity = try HonbakoRemoteMCPIdentity.create()
        item[kSecValueData as String] = try JSONEncoder().encode(identity)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw Failure.unavailable }
        return identity
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
    private enum Failure: Error { case unavailable }
}
#endif
