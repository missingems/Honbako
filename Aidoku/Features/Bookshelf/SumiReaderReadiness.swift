#if SUMI
import UIKit

extension ReaderViewController {
    /// Keep the lifted cover visible until the selected chapter's actual image
    /// is decoded, rather than opening an empty reader after metadata arrives.
    @MainActor
    func sumiWaitForOpening() async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while !Task.isCancelled, ContinuousClock.now < deadline {
            if sumiOpeningFailureMessage != nil { return false }
            view.setNeedsLayout()
            view.layoutIfNeeded()
            if let pager = reader as? ReaderPagedViewController {
                if pager.sumiOpeningImageFailed {
                    sumiOpeningFailureMessage = String(localized: "The source couldn’t load this page. Check your connection or try again.")
                    return false
                }
                pager.view.setNeedsLayout()
                pager.view.layoutIfNeeded()
                if pager.sumiReadyForOpening { return true }
            } else if let vertical = reader as? ReaderWebtoonViewController {
                if vertical.sumiOpeningImageFailed {
                    sumiOpeningFailureMessage = String(localized: "The source couldn’t load this page. Check your connection or try again.")
                    return false
                }
                vertical.view.setNeedsLayout()
                vertical.view.layoutIfNeeded()
                if vertical.sumiReadyForOpening { return true }
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
