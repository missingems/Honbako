#if SUMI
import UIKit

extension ReaderViewController {
    /// Keep the lifted cover visible until the selected chapter's actual image
    /// is decoded, rather than opening an empty reader after metadata arrives.
    @MainActor
    func sumiWaitForOpening() async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while !Task.isCancelled, ContinuousClock.now < deadline {
            view.setNeedsLayout()
            view.layoutIfNeeded()
            if let pager = reader as? ReaderPagedViewController {
                pager.view.setNeedsLayout()
                pager.view.layoutIfNeeded()
                if pager.sumiReadyForOpening { return true }
            } else if let vertical = reader as? ReaderWebtoonViewController {
                vertical.view.setNeedsLayout()
                vertical.view.layoutIfNeeded()
                if vertical.sumiReadyForOpening { return true }
            }
            do { try await Task.sleep(for: .milliseconds(40)) }
            catch { return false }
        }
        return false
    }
}
#endif
