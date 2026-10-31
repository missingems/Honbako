#if SUMI
import Darwin
import Foundation

/// The hardware model, for the few features that exist only on one device.
enum HonbakoDeviceModel {
    static let identifier: String = {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? ""
        #else
        var system = utsname()
        uname(&system)
        let capacity = MemoryLayout.size(ofValue: system.machine)
        return withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
        #endif
    }()

    /// Cover mode needs iPhone Duo's outer display.
    static var isPhoneDuo: Bool { identifier == "iPhone19,4" }
}
#endif
