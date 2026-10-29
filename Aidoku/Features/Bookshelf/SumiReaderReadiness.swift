#if SUMI
import UIKit

extension ReaderViewController {
    /// Warm the selected image briefly, then show its mounted loading or retry
    /// surface inside the navigable reader. Only unresolved chapter metadata
    /// should keep a bookmark behind the whole-book loading screen.
    @MainActor
    func sumiWaitForOpening(imageWarmup: Duration = .seconds(2)) async -> Bool {
        let started = ContinuousClock.now
        let imageDeadline = started.advanced(by: imageWarmup)
        let deadline = started.advanced(by: .seconds(30))
        while !Task.isCancelled, ContinuousClock.now < deadline {
            if sumiOpeningFailureMessage != nil { return false }
            view.setNeedsLayout()
            view.layoutIfNeeded()
            if let pager = reader as? ReaderPagedViewController {
                pager.view.setNeedsLayout()
                pager.view.layoutIfNeeded()
                if pager.sumiCanPresentOpening
                    || (ContinuousClock.now >= imageDeadline && pager.sumiCanPresentLoadingOpening) { return true }
            } else if let vertical = reader as? ReaderWebtoonViewController {
                vertical.view.setNeedsLayout()
                vertical.view.layoutIfNeeded()
                if vertical.sumiCanPresentOpening
                    || (ContinuousClock.now >= imageDeadline && vertical.sumiCanPresentLoadingOpening) { return true }
            }
            do { try await Task.sleep(for: .milliseconds(40)) }
            catch { return false }
        }
        return false
    }

    @MainActor
    func sumiAbandonOpening() {
        (reader as? ReaderPagedViewController)?.sumiAbandonOpening()
        (reader as? ReaderWebtoonViewController)?.sumiAbandonOpening()
        let source = source
        let manga = manga
        let chapter = chapter
        if let source {
            Task { await SumiChapterPageListCache.shared.invalidate(.init(source: source, manga: manga, chapter: chapter)) }
        }
    }
}
#endif
