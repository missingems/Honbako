import UIKit
import os.signpost

/// A passive frame-rate preference for native page turns. UIKit still chooses
/// the actual cadence; this creates no display link or per-frame callback.
@MainActor
final class ReaderPageTurnCadence {
    private weak var view: UIView?
    private var updateLinkStorage: AnyObject?
    private static let performanceLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "Aidoku", category: .pointsOfInterest)
    private var intervalSignpostID: OSSignpostID?

    init(view: UIView) {
        self.view = view
        #if os(iOS) && !targetEnvironment(macCatalyst)
        if #available(iOS 18.0, *) {
            let link = UIUpdateLink(view: view)
            // Both properties default to false. In particular, leave the
            // continuous-update policy untouched: this is only a passive hint.
            updateLinkStorage = link
        }
        #endif
    }

    var isActive: Bool {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        if #available(iOS 18.0, *) { return (updateLinkStorage as? UIUpdateLink)?.isEnabled == true }
        #endif
        return false
    }

    var preferredFrameRateRange: CAFrameRateRange? {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        if #available(iOS 18.0, *) { return (updateLinkStorage as? UIUpdateLink)?.preferredFrameRateRange }
        #endif
        return nil
    }

    var requiresContinuousUpdates: Bool {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        if #available(iOS 18.0, *) { return (updateLinkStorage as? UIUpdateLink)?.requiresContinuousUpdates == true }
        #endif
        return false
    }

    func setActive(_ active: Bool) {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        if #available(iOS 18.0, *), let link = updateLinkStorage as? UIUpdateLink {
            guard active, let window = view?.window, !window.isHidden,
                  let screen = window.windowScene?.screen, screen.maximumFramesPerSecond > 0 else {
                link.isEnabled = false
                link.preferredFrameRateRange = .default
                setSignpostActive(false)
                return
            }
            link.preferredFrameRateRange = Self.preferredRange(maximumFramesPerSecond: screen.maximumFramesPerSecond)
            link.isEnabled = true
            setSignpostActive(true)
            return
        }
        #endif
        setSignpostActive(false)
    }

    private func setSignpostActive(_ active: Bool) {
        if active {
            guard intervalSignpostID == nil else { return }
            let id = OSSignpostID(log: Self.performanceLog)
            os_signpost(.begin, log: Self.performanceLog, name: "NativePageCurl", signpostID: id)
            intervalSignpostID = id
        } else if let id = intervalSignpostID {
            os_signpost(.end, log: Self.performanceLog, name: "NativePageCurl", signpostID: id)
            intervalSignpostID = nil
        }
    }

    static func preferredRange(maximumFramesPerSecond: Int) -> CAFrameRateRange {
        guard maximumFramesPerSecond > 0 else { return .default }
        let maximum = Float(min(120, maximumFramesPerSecond))
        return CAFrameRateRange(minimum: min(80, maximum), maximum: maximum, preferred: maximum)
    }
}
