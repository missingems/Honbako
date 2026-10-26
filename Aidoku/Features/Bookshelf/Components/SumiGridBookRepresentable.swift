#if SUMI
import SwiftUI

struct SumiGridBookRepresentable: UIViewRepresentable {
    let book: SumiBook
    let anchor: SumiBookSourceAnchor

    func makeUIView(context: Context) -> SumiGridBookView {
        let view = SumiGridBookView(frame: .zero)
        anchor.view = view
        view.configure(book: book)
        return view
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: SumiGridBookView, context: Context) -> CGSize? {
        let width = max(1, proposal.width ?? ((proposal.height ?? 200) * CGFloat(SumiGridBookPose.coverAspect)))
        return CGSize(width: width, height: width / CGFloat(SumiGridBookPose.coverAspect))
    }

    func updateUIView(_ view: SumiGridBookView, context: Context) {
        anchor.view = view
        view.configure(book: book)
    }
}
#endif
