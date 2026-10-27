#if SUMI
import SwiftUI

struct SumiGridBookRepresentable: UIViewRepresentable {
    let book: SumiBook
    let anchor: SumiBookSourceAnchor
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> SumiGridBookView {
        let view = SumiGridBookView(frame: .zero)
        anchor.view = view
        view.configure(book: book, dynamicTypeSize: dynamicTypeSize, colorScheme: colorScheme)
        return view
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: SumiGridBookView, context: Context) -> CGSize? {
        let offeredWidth = proposal.width.flatMap { $0.isFinite ? max(1, $0) : nil }
        let offeredHeight = proposal.height.flatMap { $0.isFinite ? max(1, $0) : nil }
        if let width = offeredWidth, let height = offeredHeight {
            return CGSize(width: width, height: height)
        }
        let width = offeredWidth ?? ((offeredHeight ?? 200) * CGFloat(SumiGridBookPose.coverAspect))
        let height = width / CGFloat(SumiGridBookPose.coverAspect)
        guard width.isFinite, height.isFinite else {
            return CGSize(width: 200 * CGFloat(SumiGridBookPose.coverAspect), height: 200)
        }
        return CGSize(width: width, height: height)
    }

    func updateUIView(_ view: SumiGridBookView, context: Context) {
        anchor.view = view
        view.configure(book: book, dynamicTypeSize: dynamicTypeSize, colorScheme: colorScheme)
    }
}
#endif
