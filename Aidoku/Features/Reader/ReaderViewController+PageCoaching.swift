#if SUMI
import UIKit

extension ReaderViewController {
    var sumiMayShareAssistantPage: Bool {
        #if DEBUG
        if HonbakoPageAccessPreview.permits(manga) { return true }
        #endif
        return !AppSettings.general.incognitoMode.get()
    }

    /// The paired connection owns page access. Opening a reader only supplies
    /// its visible canonical page; it never presents or dismisses reader UI.
    func sumiFollowAssistantPageAccess() {
        guard sumiCanFollowAssistantPageAccess else { return }
        HonbakoPageCoachingService.shared.follow(owner: self) { [weak self] in
            self?.sumiPageCoachingCapture()
        }
    }
}
#endif
