#if SUMI
import SwiftUI

extension ReaderViewController {
    var sumiJapaneseLearningAvailable: Bool {
        HonbakoJapaneseLanguageEligibility.allows(chapterLanguage: chapter.language, sourceLanguages: source?.languages ?? [])
            || HonbakoJapaneseLanguageEligibility.containsOriginalPracticePage(sourceKey: manga.sourceKey,
                mangaKey: manga.key, chapterKey: chapter.key)
    }

    var sumiJapaneseLearningPolicy: HonbakoJapaneseLearningPolicy {
        .init(requested: sumiJapaneseLearningEnabled, languageEligible: sumiJapaneseLearningAvailable,
            hasPro: HonbakoProStore.cachedHasPro)
    }

    func sumiJapaneseProAccessChanged() {
        if !HonbakoProStore.cachedHasPro {
            sumiJapaneseLearningEnabled = false
            sumiDismissJapanesePhrase(resumeAutoScroll: false)
        }
        sumiConfigureJapaneseLearning()
    }

    func sumiConfigureJapaneseLearning() {
        guard let imageReader = reader as? HonbakoJapaneseReader else { return }
        let enabled = sumiJapaneseLearningPolicy.enabled
        imageReader.configureJapaneseLearning(enabled: enabled) { [weak self] region, wordID, anchor in
            self?.sumiShowJapanesePhrase(region: region, wordID: wordID, windowAnchor: anchor)
        }
        imageReader.setJapaneseLearningActive(sumiJapaneseLearningActive && enabled)
    }

    func sumiSetJapaneseLearningEnabled(_ enabled: Bool) {
        sumiJapaneseLearningEnabled = enabled && HonbakoProStore.cachedHasPro
        if !sumiJapaneseLearningEnabled { sumiDismissJapanesePhrase(resumeAutoScroll: true) }
        sumiConfigureJapaneseLearning()
    }

    func sumiSetJapaneseLearningActive(_ active: Bool) {
        sumiJapaneseLearningActive = active
        if !active { sumiDismissJapanesePhrase(resumeAutoScroll: false) }
        (reader as? HonbakoJapaneseReader)?.setJapaneseLearningActive(active && sumiJapaneseLearningPolicy.enabled)
    }

    /// The page remains mounted; only the selected phrase uses a native presentation.
    private func sumiShowJapanesePhrase(region: HonbakoJapaneseRegion, wordID: Int?, windowAnchor: CGRect) {
        guard sumiJapaneseLearningPolicy.enabled, sumiJapaneseLearningActive,
              presentedViewController == nil, view.window != nil,
              view.window?.windowScene?.activationState == .foregroundActive else { return }
        let scrollingReader = reader as? ReaderWebtoonViewController
        let shouldResume = scrollingReader?.sumiIsAutoScrollActivelyRunning == true
        sumiJapanesePopupOwnsAutoScroll = true
        if shouldResume { scrollingReader?.pauseAutoScroll() }
        let panel = HonbakoJapanesePhraseController(rootView: HonbakoJapanesePhraseView(
            text: region.text, confidence: region.confidence, initialWordID: wordID))
        panel.onFinished = { [weak self, weak scrollingReader, weak panel] in
            guard let self else { return }
            let isCurrent = sumiJapanesePhraseController === panel
            if isCurrent {
                sumiJapanesePhraseController = nil
                sumiJapanesePhraseViewport = nil
                sumiJapanesePopupOwnsAutoScroll = false
            }
            if isCurrent, shouldResume, sumiJapaneseLearningActive, sumiJapaneseLearningPolicy.enabled,
               viewIfLoaded?.window != nil, view.window?.windowScene?.activationState == .foregroundActive {
                scrollingReader?.resumeAutoScroll()
            }
        }
        panel.view.tintColor = .label
        panel.view.backgroundColor = .systemGroupedBackground
        panel.modalPresentationStyle = .popover
        panel.preferredContentSize = CGSize(width: 360, height: min(560, max(320, view.bounds.height - 48)))
        let anchor = view.convert(windowAnchor, from: nil).intersection(view.bounds.inset(by: view.safeAreaInsets))
        panel.popoverPresentationController?.sourceView = view
        panel.popoverPresentationController?.sourceRect = anchor.isNull ? CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1) : anchor
        panel.popoverPresentationController?.backgroundColor = .systemGroupedBackground
        let adaptiveSheet = panel.popoverPresentationController?.adaptiveSheetPresentationController
        adaptiveSheet?.detents = [.medium(), .large()]
        adaptiveSheet?.prefersGrabberVisible = true
        adaptiveSheet?.prefersEdgeAttachedInCompactHeight = true
        adaptiveSheet?.widthFollowsPreferredContentSizeWhenEdgeAttached = true
        sumiJapanesePhraseController = panel
        sumiJapanesePhraseViewport = view.bounds.size
        present(panel, animated: true)
    }

    func sumiDismissJapanesePhrase(resumeAutoScroll: Bool) {
        guard let panel = sumiJapanesePhraseController else { return }
        if !resumeAutoScroll {
            // Clear ownership first so navigation/closing cannot restart scrolling.
            sumiJapanesePhraseController = nil
            sumiJapanesePhraseViewport = nil
            sumiJapanesePopupOwnsAutoScroll = false
        }
        panel.dismiss(animated: false)
    }
}

private final class HonbakoJapanesePhraseController: UIHostingController<HonbakoJapanesePhraseView> {
    var onFinished: (() -> Void)?

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || presentingViewController == nil else { return }
        let finish = onFinished
        onFinished = nil
        finish?()
    }
}
#endif
