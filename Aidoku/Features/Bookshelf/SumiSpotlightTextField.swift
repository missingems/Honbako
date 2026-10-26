#if SUMI
import UIKit

final class SumiSpotlightTextField: UISearchTextField {
    var dismissSearch: (() -> Void)?
    var acceptsSearchFocus = true {
        didSet {
            guard oldValue != acceptsSearchFocus else { return }
            isAccessibilityElement = acceptsSearchFocus
            accessibilityElementsHidden = !acceptsSearchFocus
            synchronizeFocus()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, acceptsSearchFocus else { return }
        synchronizeFocus()
    }

    private func synchronizeFocus() {
        // Leave SwiftUI's update transaction before requesting the native
        // keyboard transition. Keep this field mounted while it slides away.
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            if self.acceptsSearchFocus {
                guard self.window != nil else { return }
                self.becomeFirstResponder()
            } else {
                self.resignFirstResponder()
            }
        }
    }

    override var keyCommands: [UIKeyCommand]? {
        (super.keyCommands ?? []) + [UIKeyCommand(input: UIKeyCommand.inputEscape,
            modifierFlags: [], action: #selector(dismissOverlay), discoverabilityTitle: "Close Search")]
    }

    @objc private func dismissOverlay() { dismissSearch?() }
}
#endif
