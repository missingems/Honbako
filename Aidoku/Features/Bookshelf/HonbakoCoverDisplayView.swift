#if SUMI
import SwiftUI

/// A matte print on the outer display. Tone only this accessory, never the
/// reader or the hardware brightness shared with other app windows.
struct HonbakoCoverDisplayView: View {
    @ObservedObject var model: HonbakoCoverDisplayModel

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(white: 0.10)
                if let image = model.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .colorMultiply(Color(white: 0.78))
                        .overlay {
                            Image(uiImage: SumiPaperSurface.inkTile)
                                .resizable(resizingMode: .tile)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    Text(model.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color(white: 0.78))
                        .multilineTextAlignment(.center)
                        .padding(24)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .accessibilityLabel(model.title)
    }
}
#endif
