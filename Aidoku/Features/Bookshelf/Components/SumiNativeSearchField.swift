#if SUMI
import SwiftUI
import UIKit

struct SumiNativeSearchField: UIViewRepresentable {
    @Binding var text: String
    var isActive = true
    var requestsKeyboard = true
    var entryOnly = false
    let dismiss: () -> Void
    let keyboardDismissed: () -> Void
    let beginSearch: () -> Void

    func makeUIView(context: Context) -> SumiNativeSearchTextField {
        let field = SumiNativeSearchTextField()
        field.placeholder = String(localized: "Search Manga")
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.backgroundColor = .secondarySystemFill
        field.borderStyle = .none
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.returnKeyType = .search
        field.clearButtonMode = .whileEditing
        field.accessibilityIdentifier = entryOnly ? "Honbako.Library.SearchEntry" : "Sumi.Search.Field"
        field.accessibilityLabel = String(localized: "Search Manga")
        field.isAccessibilityElement = true
        field.accessibilityElementsHidden = false
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.dismissSearch = dismiss
        field.acceptsSearchFocus = isActive
        field.requestsSearchFocus = requestsKeyboard
        return field
    }

    func updateUIView(_ field: SumiNativeSearchTextField, context: Context) {
        context.coordinator.parent = self
        field.dismissSearch = dismiss
        field.acceptsSearchFocus = isActive
        field.requestsSearchFocus = requestsKeyboard
        if field.text != text { field.text = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: SumiNativeSearchTextField, context: Context) -> CGSize? {
        CGSize(width: max(80, proposal.width ?? 220), height: max(36, uiView.intrinsicContentSize.height))
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SumiNativeSearchField
        init(parent: SumiNativeSearchField) { self.parent = parent }
        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }
        func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
            guard parent.entryOnly else { return true }
            parent.beginSearch()
            return false
        }
        func textFieldDidBeginEditing(_ textField: UITextField) { parent.beginSearch() }
        func textFieldDidEndEditing(_ textField: UITextField) { parent.keyboardDismissed() }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}

#endif
