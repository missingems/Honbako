#if SUMI
import SwiftUI

struct SumiBookGridCell: View {
    let book: SumiBook
    var body: some View {
        PhysicalBookView(book: book.presentation, style: .shelf)
            .frame(maxWidth: 250)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
            .contentShape(.rect)
            .accessibilityHidden(true)
    }
}
#endif
