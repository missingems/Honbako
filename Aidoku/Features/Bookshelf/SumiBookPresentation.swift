#if SUMI
import SwiftUI
import UIKit

/// One presentation path for books opened from either library arrangement or Search.
@MainActor
enum SumiBookPresentation {
    static func present(_ book: SumiBook, store: SumiLibraryStore, from presenter: UIViewController, visibility: SumiLibraryVisibility? = nil, source: SumiBookTransitionSource? = nil) {
        guard presenter.presentedViewController == nil else { source?.finish(); return }
        #if DEBUG
        let diagnostics = SumiBookZoomPreviewDiagnostics(bookID: book.presentation.id)
        #endif
        presenter.view.endEditing(true)
        let controller = UIHostingController(rootView: SumiBookDetailView(book: book, store: store))
        controller.view.accessibilityIdentifier = "Sumi.Book.Open.\(book.presentation.id)"
        controller.view.backgroundColor = .clear
        controller.view.isOpaque = false
        controller.navigationItem.largeTitleDisplayMode = .never
        let presentation = SumiBookNavigationController(rootViewController: controller)
        presentation.onBookDismissed = { [weak visibility] in
            source?.finish()
            #if DEBUG
            diagnostics?.recordDismissal()
            #endif
            visibility?.isObscured = false
        }
        presentation.modalPresentationStyle = .overFullScreen
        let options = UIViewController.Transition.ZoomOptions()
        options.dimmingColor = .clear
        options.alignmentRectProvider = { context in
            context.zoomedViewController.loadViewIfNeeded()
            guard let view = context.zoomedViewController.viewIfLoaded else { return nil }
            view.layoutIfNeeded()
            guard let target = zoomTarget(in: view), !target.bounds.isEmpty else { return nil }
            let rect = target.convert(target.bounds, to: view)
            #if DEBUG
            diagnostics?.recordTarget(rect)
            #endif
            return rect
        }
        presentation.preferredTransition = .zoom(options: options) { [weak source] _ in
            let view = source?.view
            #if DEBUG
            diagnostics?.recordSource(view)
            #endif
            guard let view, view.window != nil else { return nil }
            return view
        }
        presentation.view.backgroundColor = .clear
        presentation.view.isOpaque = false
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        presentation.navigationBar.standardAppearance = appearance
        presentation.navigationBar.scrollEdgeAppearance = appearance
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak presentation] _ in
            presentation?.dismiss(animated: true)
        })
        controller.navigationItem.leftBarButtonItem?.accessibilityIdentifier = "SumiCloseBook"
        controller.navigationItem.leftBarButtonItem?.accessibilityLabel = "Close book"
        visibility?.isObscured = true
        presenter.present(presentation, animated: true)
    }
    private static func zoomTarget(in view: UIView) -> UIView? {
        if view.accessibilityIdentifier == "Sumi.Book.ZoomTarget" { return view }
        for child in view.subviews {
            if let target = zoomTarget(in: child) { return target }
        }
        return nil
    }
}
#endif
