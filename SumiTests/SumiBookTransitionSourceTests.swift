@testable import Sumi
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct SumiBookTransitionSourceTests {
    private final class ArtworkView: UIImageView, SumiGridBookArtworkProviding {
        var coverArtwork: UIImage?
        var bookPose = SumiGridBookPose(seed: 129)
    }

    private func image(color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 30, height: 40), format: format).image { context in
            color.setFill()
            context.fill(CGRect(x: 4, y: 5, width: 20, height: 30))
        }
    }

    @Test("A pickup preserves rendered alpha and color and carries raw print separately from the physical pose")
    func preservesSourcePixelsAndMetadata() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousKeyWindow = scene.keyWindow
        let host = UIViewController()
        host.view.backgroundColor = .black
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.windowLevel = .alert + 1
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            let wasKeyWindow = window.isKeyWindow
            window.isHidden = true
            window.rootViewController = nil
            if wasKeyWindow { previousKeyWindow?.makeKey() }
        }
        let rendered = image(color: UIColor(red: 0.7, green: 0.2, blue: 0.4, alpha: 0.55))
        let print = image(color: UIColor(red: 0.1, green: 0.8, blue: 0.5, alpha: 1))
        let anchor = ArtworkView(frame: CGRect(x: 40, y: 80, width: 152, height: 200))
        anchor.image = rendered
        anchor.coverArtwork = print
        anchor.alpha = 0.28
        host.view.addSubview(anchor)
        window.layoutIfNeeded()

        let source = try #require(SumiBookTransitionSource.capture(anchor))
        let proxy = try #require(source.view as? UIImageView)
        #expect(proxy.image?.pngData() == rendered.pngData(), "A dimmed window must not bake its gray background or opacity into the physical cover")
        #expect(proxy.image?.scale == rendered.scale)
        #expect(proxy.frame == anchor.bounds)
        #expect(source.coverArtwork?.pngData() == print.pngData(), "The transition textures the book with raw print, never an already-lit 3D snapshot")
        #expect(source.closedPose == anchor.bookPose)

        // Later model updates cannot silently retarget a book already held by
        // the reader. Its return uses the exact captured edition and pose.
        anchor.coverArtwork = image(color: .blue)
        anchor.bookPose = SumiGridBookPose(seed: 999)
        #expect(source.coverArtwork?.pngData() == print.pngData())
        #expect(source.closedPose == SumiGridBookPose(seed: 129))
        #expect(proxy.superview === anchor)
        source.finish()
        #expect(proxy.superview == nil)
        source.finish()
        #expect(proxy.superview == nil)
    }

    @Test("A returning book keeps its measured slot when a lazy grid replaces its original view")
    func orphanedSourceReconnectsToItsGridSlot() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.windowLevel = .alert + 1
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            let wasKeyWindow = window.isKeyWindow
            window.isHidden = true
            window.rootViewController = nil
            if wasKeyWindow { previousKeyWindow?.makeKey() }
        }
        // An offset container also verifies that captured window coordinates
        // are converted back, rather than used as a centered fallback frame.
        let container = UIView(frame: CGRect(x: 22, y: 18, width: 400, height: 400))
        host.view.addSubview(container)
        let originalFrame = CGRect(x: 40, y: 80, width: 152, height: 200)
        let anchor = ArtworkView(frame: originalFrame)
        anchor.image = image(color: .red)
        anchor.coverArtwork = anchor.image
        container.addSubview(anchor)
        var currentAnchor: UIView? = anchor
        window.layoutIfNeeded()
        let source = try #require(SumiBookTransitionSource.capture(anchor, replacementView: { currentAnchor }))
        defer { source.finish() }
        #expect(source.frame(in: container) == originalFrame)

        anchor.removeFromSuperview()
        #expect(source.view.window == nil)
        #expect(source.frame(in: container) == originalFrame,
                "Full-screen presentation must not retarget an orphaned book to the middle of the library")
        #expect(source.frame(in: host.view) == container.convert(originalFrame, to: host.view))

        let replacementFrame = CGRect(x: 206, y: 44, width: 114, height: 150)
        let replacement = ArtworkView(frame: replacementFrame)
        replacement.image = image(color: .blue)
        container.addSubview(replacement)
        currentAnchor = replacement
        window.layoutIfNeeded()
        #expect(source.frame(in: container) == replacementFrame,
                "A recreated live cell is authoritative after layout or device size changes")
        #expect(source.frame(in: host.view) == replacement.convert(replacement.bounds, to: host.view))
        #expect(source.view.window == nil, "The new slot must work independently of the detached snapshot")
    }

    @Test("An unrendered RealityKit source cannot fall back to a composited window screenshot")
    func unrenderedProviderDoesNotCaptureDimming() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        let anchor = ArtworkView(frame: CGRect(x: 20, y: 20, width: 100, height: 140))
        anchor.coverArtwork = image(color: .red)
        host.view.addSubview(anchor)
        window.layoutIfNeeded()
        #expect(anchor.window != nil)
        #expect(SumiBookTransitionSource.capture(anchor) == nil)
    }
}
