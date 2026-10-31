#if SUMI
import Darwin
import UIKit

/// Provenance travels with the bookmark, so a synced page names the device
/// that actually recorded it. Older bookmarks intentionally remain unnamed.
enum SumiReadingProvenance {
    struct Device: Sendable {
        let id: String
        let name: String
    }

    @MainActor static var currentDevice: Device {
        let defaults = UserDefaults.standard
        let key = "Data.sumi.readingDeviceID"
        let id: String
        if let vendorID = UIDevice.current.identifierForVendor?.uuidString {
            id = vendorID
            defaults.set(id, forKey: key)
        }
        else if let saved = defaults.string(forKey: key), !saved.isEmpty { id = saved }
        else { id = UUID().uuidString; defaults.set(id, forKey: key) }
        let device = UIDevice.current
        var name = device.name
        if ["iPhone", "iPad", "iPod touch"].contains(name) {
            let machine = HonbakoDeviceModel.identifier
            if HonbakoDeviceModel.isPhoneDuo { name = "iPhone Duo" }
            else if ["iPad16,1", "iPad16,2"].contains(machine) { name = "iPad mini" }
        }
        return Device(id: id, name: name)
    }

    static func deviceLabel(for history: HistoryObject) -> String? {
        guard history.entity.attributesByName["readDeviceID"] != nil else { return nil }
        return deviceLabel(id: history.readDeviceID, name: history.readDeviceName,
                           currentID: UserDefaults.standard.string(forKey: "Data.sumi.readingDeviceID"))
    }

    static func deviceLabel(id: String?, name: String?, currentID: String?) -> String? {
        guard let id, !id.isEmpty, let name = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
        return id == currentID ? String(localized: "This device") : name
    }
}
#endif
