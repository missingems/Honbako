#if SUMI || HONBAKO_WIDGET_EXTENSION
import SwiftUI
import UIKit
import WidgetKit

struct HonbakoWidgetCover: View {
    let book: HonbakoWidgetSnapshot.Book?
    var body: some View {
        GeometryReader { geometry in
            Group {
                if let url = HonbakoWidgetSnapshot.coverURL(file: book?.coverFile),
                   let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image)
                        .resizable()
                        .widgetAccentedRenderingMode(.fullColor)
                        .scaledToFill()
                } else if book?.sourceID == "preview" {
                    ZStack {
                        HonbakoPalette.action
                        Circle().stroke(.white.opacity(0.9), lineWidth: 2)
                            .frame(width: geometry.size.width * 0.6)
                            .offset(x: geometry.size.width * 0.2, y: -geometry.size.height * 0.2)
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: geometry.size.height * 0.7))
                            path.addLine(to: CGPoint(x: geometry.size.width * 0.5, y: geometry.size.height * 0.32))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height * 0.7))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                            path.addLine(to: CGPoint(x: 0, y: geometry.size.height))
                            path.closeSubpath()
                        }.fill(.white.opacity(0.18))
                        Text(book?.title ?? "")
                            .font(.system(size: geometry.size.width * 0.16, weight: .black, design: .serif))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.5)
                            .padding(max(2, min(10, geometry.size.width * 0.08)))
                    }
                } else {
                    ZStack {
                        HonbakoPalette.accent.opacity(0.18)
                        Image(systemName: "book.closed.fill")
                            .font(.largeTitle)
                            .foregroundStyle(HonbakoPalette.accent)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .clipShape(.rect(cornerRadius: 7))
        .accessibilityHidden(true)
    }
}

#endif
