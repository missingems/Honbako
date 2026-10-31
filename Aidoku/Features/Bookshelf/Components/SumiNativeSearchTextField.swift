#if SUMI
import UIKit

final class SumiNativeSearchTextField: UISearchTextField {
    var dismissSearch: (() -> Void)?
    var requestsSearchFocus = true {
        didSet {
            guard oldValue != requestsSearchFocus else { return }
            synchronizeFocus()
        }
    }
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
        // keyboard transition. The toolbar keeps its native field mounted while reading.
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            if self.acceptsSearchFocus, self.requestsSearchFocus {
                guard self.window != nil else { return }
                self.becomeFirstResponder()
            } else {
                self.resignFirstResponder()
            }
        }
    }

    override var keyCommands: [UIKeyCommand]? {
        (super.keyCommands ?? []) + [UIKeyCommand(input: UIKeyCommand.inputEscape,
            modifierFlags: [], action: #selector(dismissNativeSearch), discoverabilityTitle: "Close Search")]
    }

    @objc private func dismissNativeSearch() { dismissSearch?() }
}
#endif
