#if SUMI && DEBUG
import UIKit

/// Explicit fixture-run diagnostics only. No console output or release code.
@MainActor
enum SumiBookPinchDiagnostics {
    private static let enabled = ProcessInfo.processInfo.arguments.contains("--sumi-pinch-diagnostics")
    private static let file = FileManager.default.cachesDirectory.appendingPathComponent("SumiPinchDiagnostics.jsonl")
    private static var reset = false
    static var isEnabled: Bool { enabled }

    static func resetIfNeeded() {
        guard enabled, !reset else { return }
        reset = true
        try? Data().write(to: file, options: .atomic)
    }

    static func record(_ event: String, _ details: [String: Any] = [:]) {
        guard enabled else { return }
        resetIfNeeded()
        var payload = details
        payload["event"] = event
        payload["time"] = CACurrentMediaTime()
        guard var data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let handle = try? FileHandle(forWritingTo: file) else { return }
        defer { try? handle.close() }
        guard let offset = try? handle.seekToEnd(), offset < 65_536 else { return }
        data.append(0x0A)
        try? handle.write(contentsOf: data)
    }

    static func typeName(_ object: AnyObject?) -> String {
        object.map { String(describing: type(of: $0)) } ?? "nil"
    }

    static func number(_ value: CGFloat) -> Any {
        if value.isFinite { return Double(value) }
        return String(describing: value)
    }

    static func ancestry(of view: UIView?) -> [[String: Any]] {
        var result: [[String: Any]] = []
        var current = view
        while let view = current, result.count < 16 {
            result.append(["class": typeName(view), "identifier": view.accessibilityIdentifier ?? "",
                           "isControl": view is UIControl, "windowClass": typeName(view.window),
                           "enabled": view.isUserInteractionEnabled, "hidden": view.isHidden,
                           "alpha": number(view.alpha), "frame": String(describing: view.frame),
                           "accessibilityHidden": view.accessibilityElementsHidden])
            current = view.superview
        }
        return result
    }
}
#endif
