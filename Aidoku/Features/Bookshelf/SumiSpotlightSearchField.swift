#if SUMI
import SwiftUI
import UIKit

struct SumiSpotlightSearchField: UIViewRepresentable {
    @Binding var text: String
    var isActive = true
    var requestsKeyboard = true
    let dismiss: () -> Void

    func makeUIView(context: Context) -> SumiSpotlightTextField {
        let field = SumiSpotlightTextField()
        field.placeholder = "Search manga"
        field.font = .preferredFont(forTextStyle: .title3)
        field.adjustsFontForContentSizeCategory = true
        field.backgroundColor = .clear
        field.borderStyle = .none
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.returnKeyType = .search
        field.clearButtonMode = .whileEditing
        field.accessibilityIdentifier = "Sumi.Search.Field"
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.dismissSearch = dismiss
        field.acceptsSearchFocus = isActive
        field.requestsSearchFocus = requestsKeyboard
        return field
    }

    func updateUIView(_ field: SumiSpotlightTextField, context: Context) {
        context.coordinator.parent = self
        field.dismissSearch = dismiss
        field.acceptsSearchFocus = isActive
        field.requestsSearchFocus = requestsKeyboard
        if field.text != text { field.text = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SumiSpotlightSearchField
        init(parent: SumiSpotlightSearchField) { self.parent = parent }
        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}

#endif
