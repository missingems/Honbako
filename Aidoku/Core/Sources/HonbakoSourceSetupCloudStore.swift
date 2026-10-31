#if SUMI
import Foundation

@MainActor
protocol HonbakoSourceSetupCloudStore: AnyObject {
    var keys: [String] { get }
    func data(forKey key: String) -> Data?
    func set(_ value: Data, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

@MainActor
final class HonbakoUbiquitousSourceSetupStore: HonbakoSourceSetupCloudStore {
    private let store = NSUbiquitousKeyValueStore.default
    var keys: [String] { Array(store.dictionaryRepresentation.keys) }
    func data(forKey key: String) -> Data? { store.data(forKey: key) }
    func set(_ value: Data, forKey key: String) { store.set(value, forKey: key) }
    func synchronize() -> Bool { store.synchronize() }
}
#endif
