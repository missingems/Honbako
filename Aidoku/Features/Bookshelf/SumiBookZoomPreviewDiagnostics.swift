#if SUMI && DEBUG
import UIKit

/// Evidence from generated books only; never reads or exports a real library.
@MainActor
final class SumiBookZoomPreviewDiagnostics {
    private var payload: [String: Any]
    private var sourceRequests = 0
    private var alignmentRequests = 0

    init?(bookID: String) {
        guard ProcessInfo.processInfo.arguments.contains("--sumi-library-check")
                || ProcessInfo.processInfo.arguments.contains("--sumi-grid-check") else { return nil }
        payload = ["bookID": bookID, "transition": "UIKit native zoom", "dismissed": false]
        write()
    }

    func recordSource(_ view: UIView?) {
        sourceRequests += 1
        payload["sourceRequests"] = sourceRequests
        payload["sourceHasWindow"] = view?.window != nil
        if let view, let window = view.window {
            payload["sourceFrame"] = rect(view.convert(view.bounds, to: window))
        }
        write()
    }

    func recordTarget(_ frame: CGRect) {
        alignmentRequests += 1
        payload["alignmentRequests"] = alignmentRequests
        payload["targetFrame"] = rect(frame)
        write()
    }

    func recordDismissal() {
        payload["dismissed"] = true
        write()
    }

    private func rect(_ frame: CGRect) -> [CGFloat] { [frame.minX, frame.minY, frame.width, frame.height] }

    private func write() {
        guard let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: cache.appendingPathComponent("SumiBookZoomPreviewDiagnostics.json"), options: .atomic)
    }
}
#endif
