#if SUMI
import SwiftUI
import UIKit

/// The visible book that UIKit lifts into its detail presentation.
@MainActor
final class SumiBookTransitionSource {
    let view: UIView
    let coverArtwork: UIImage?
    let closedPose: SumiGridBookPose?
    private var cleanup: (() -> Void)?
    private let capturedFrame: CGRect?
    private let capturedViewport: CGSize?
    private let replacementView: (() -> UIView?)?

    init(view: UIView, coverArtwork: UIImage? = nil, closedPose: SumiGridBookPose? = nil, capturedFrame: CGRect? = nil, capturedViewport: CGSize? = nil, replacementView: (() -> UIView?)? = nil, cleanup: @escaping () -> Void = {}) {
        self.view = view
        self.coverArtwork = coverArtwork
        self.closedPose = closedPose
        self.capturedFrame = capturedFrame
        self.capturedViewport = capturedViewport
        self.replacementView = replacementView
        self.cleanup = cleanup
        view.accessibilityIdentifier = "Sumi.Book.ZoomSource"
    }

    func finish() {
        let action = cleanup
        cleanup = nil
        action?()
    }

    /// Full-screen presentation can discard a lazy grid's native cover view.
    /// Keep its measured destination and reconnect through its stable anchor.
    func frame(in container: UIView) -> CGRect? {
        if let current = replacementView?(), current.window != nil {
            return current.convert(current.bounds, to: container)
        }
        if view.window != nil { return view.convert(view.bounds, to: container) }
        guard let capturedFrame, let capturedViewport, let window = container.window else { return nil }
        let scaleX = window.bounds.width / max(1, capturedViewport.width)
        let scaleY = window.bounds.height / max(1, capturedViewport.height)
        let rect = CGRect(x: capturedFrame.minX * scaleX, y: capturedFrame.minY * scaleY,
                          width: capturedFrame.width * scaleX, height: capturedFrame.height * scaleY)
        return window.convert(rect, to: container)
    }

    static func capture(_ anchor: UIView, replacementView: (() -> UIView?)? = nil) -> SumiBookTransitionSource? {
        guard let window = anchor.window, !anchor.bounds.isEmpty else { return nil }
        let rect = anchor.convert(anchor.bounds, to: window)
        guard rect.width > 1, rect.height > 1 else { return nil }
        let provider = anchor as? SumiGridBookArtworkProviding
        // Preserve the rendered canvas and its alpha. A window screenshot
        // includes background dimming and bakes it into the cover on return.
        let image: UIImage
        if let rendered = (anchor as? UIImageView)?.image { image = rendered }
        else if provider != nil { return nil }
        else {
            image = UIGraphicsImageRenderer(size: rect.size).image { context in
                context.cgContext.translateBy(x: -rect.minX, y: -rect.minY)
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
            }
        }
        provider?.beginBookTransition()
        let proxy = UIImageView(image: image)
        proxy.frame = anchor.bounds
        proxy.isUserInteractionEnabled = false
        anchor.addSubview(proxy)
        return SumiBookTransitionSource(view: proxy, coverArtwork: provider?.coverArtwork, closedPose: provider?.renderedBookPose,
            capturedFrame: rect, capturedViewport: window.bounds.size, replacementView: replacementView) { [weak proxy, weak provider] in
            proxy?.removeFromSuperview()
            provider?.endBookTransition()
        }
    }
}

/// The cover's real layout rectangle, used by UIKit's native zoom alignment.
struct SumiBookZoomTarget: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.accessibilityIdentifier = "Sumi.Book.ZoomTarget"
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {}
}

@MainActor
final class SumiBookSourceAnchor {
    weak var view: UIView?
}

struct SumiBookSourceView: UIViewRepresentable {
    let anchor: SumiBookSourceAnchor
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        anchor.view = view
        return view
    }
    func updateUIView(_ view: UIView, context: Context) { anchor.view = view }
}
#endif
