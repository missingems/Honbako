#if SUMI
import SwiftUI

struct SumiLibraryLoadingCard: View {
    let shimmerPhase: Double?

    var body: some View {
        Rectangle()
            .fill(Color(uiColor: .secondarySystemFill))
            .overlay {
                if let shimmerPhase {
                    GeometryReader { geometry in
                        LinearGradient(colors: [.clear, .white.opacity(0.07), .clear],
                            startPoint: .leading, endPoint: .trailing)
                            .frame(width: geometry.size.width * 0.8, height: geometry.size.height * 2)
                            .rotationEffect(.degrees(25))
                            .offset(x: geometry.size.width * (shimmerPhase * 3.6 - 1.4),
                                y: -geometry.size.height * 0.5)
                    }
                }
            }
            .clipped()
    }
}
#endif
