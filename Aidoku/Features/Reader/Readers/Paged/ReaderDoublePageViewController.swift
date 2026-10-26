//
//  ReaderDoublePageViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/19/22.
//

import UIKit

class ReaderDoublePageViewController: BaseObservingViewController {

    enum Direction {
        case rtl
        case ltr
    }

    lazy var zoomView = ZoomableScrollView(frame: view.bounds)
    private let pageStack = UIStackView()
    private let bookSpineView = ReaderBookSpineView()
    let firstPageController: ReaderPageViewController
    let secondPageController: ReaderPageViewController

    private lazy var firstReloadButton = UIButton(type: .roundedRect)
    private lazy var secondReloadButton = UIButton(type: .roundedRect)

    var direction: Direction {
        didSet {
            if direction != oldValue, let first = pageStack.arrangedSubviews.first {
                pageStack.addArrangedSubview(first)
                view.setNeedsLayout()
            }
        }
    }

    private var firstPageSet = false
    private var secondPageSet = false
    private var firstPage: Page?
    private var secondPage: Page?
    private var pageLayoutConstraints: [NSLayoutConstraint] = []

    init(firstPage: ReaderPageViewController, secondPage: ReaderPageViewController, direction: Direction) {
        self.firstPageController = firstPage
        self.secondPageController = secondPage
        self.direction = direction
        super.init()
        self.firstPageController.isInDoublePageController = true
        self.secondPageController.isInDoublePageController = true
    }

    override func configure() {
        updateDoubleTapZoomSetting()
        zoomView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(zoomView)

        pageStack.axis = .horizontal
        pageStack.distribution = .fillEqually
        pageStack.alignment = .center
        pageStack.translatesAutoresizingMaskIntoConstraints = false
        zoomView.addSubview(pageStack)
        pageStack.addSubview(bookSpineView)
        zoomView.zoomView = pageStack
        zoomView.pageContentFrame = { [weak self] in
            guard let self, self.pageStack.arrangedSubviews.count == 2 else { return nil }
            let frames = [self.firstPageController, self.secondPageController].compactMap { controller -> CGRect? in
                guard let imageView = controller.pageView?.imageView, let image = imageView.image else { return nil }
                let frame = ReaderPageSizingGeometry.aspectFitFrame(imageSize: image.size, in: imageView.bounds)
                guard !frame.isEmpty else { return nil }
                return imageView.convert(frame, to: self.pageStack)
            }
            guard frames.count == 2 else { return nil }
            return frames[0].union(frames[1])
        }
        zoomView.onZoomScaleChanged = { [weak self] scale in
            guard let self else { return }
            for controller in [self.firstPageController, self.secondPageController] {
                controller.pageView?.setLiveTextHidden(scale != 1 || (controller.delegate?.barsHidden ?? false))
            }
        }

        firstReloadButton.isHidden = true
        firstReloadButton.setTitle(NSLocalizedString("RELOAD"), for: .normal)
        firstReloadButton.addTarget(self, action: #selector(reload(_:)), for: .touchUpInside)
        firstReloadButton.configuration = .borderless()
        firstReloadButton.configuration?.contentInsets = .init(top: 15, leading: 15, bottom: 15, trailing: 15)
        firstReloadButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(firstReloadButton)

        secondReloadButton.isHidden = true
        secondReloadButton.setTitle(NSLocalizedString("RELOAD"), for: .normal)
        secondReloadButton.addTarget(self, action: #selector(reload(_:)), for: .touchUpInside)
        secondReloadButton.configuration = .borderless()
        secondReloadButton.configuration?.contentInsets = .init(top: 15, leading: 15, bottom: 15, trailing: 15)
        secondReloadButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(secondReloadButton)
    }

    override func constrain() {
        // Keep the spread's artwork geometry fixed while controls appear or
        // disappear; interactive reader controls still use the safe area.
        NSLayoutConstraint.activate([
            zoomView.topAnchor.constraint(equalTo: view.topAnchor),
            zoomView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            zoomView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            zoomView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            pageStack.topAnchor.constraint(equalTo: zoomView.contentLayoutGuide.topAnchor),
            pageStack.leadingAnchor.constraint(equalTo: zoomView.contentLayoutGuide.leadingAnchor),
            pageStack.trailingAnchor.constraint(equalTo: zoomView.contentLayoutGuide.trailingAnchor),
            pageStack.bottomAnchor.constraint(equalTo: zoomView.contentLayoutGuide.bottomAnchor),
            pageStack.widthAnchor.constraint(lessThanOrEqualTo: zoomView.frameLayoutGuide.widthAnchor),
            pageStack.heightAnchor.constraint(equalTo: zoomView.frameLayoutGuide.heightAnchor)
        ])

        guard
            let firstPageView = firstPageController.pageView,
            let secondPageView = secondPageController.pageView
        else {
            return
        }

        pageLayoutConstraints = [
            firstPageView.widthAnchor.constraint(equalTo: firstPageView.imageView.widthAnchor),
            firstPageView.heightAnchor.constraint(equalTo: pageStack.heightAnchor),
            secondPageView.widthAnchor.constraint(equalTo: secondPageView.imageView.widthAnchor),
            secondPageView.heightAnchor.constraint(equalTo: pageStack.heightAnchor),

            firstReloadButton.centerXAnchor.constraint(equalTo: firstPageView.centerXAnchor),
            firstReloadButton.centerYAnchor.constraint(equalTo: firstPageView.centerYAnchor),

            secondReloadButton.centerXAnchor.constraint(equalTo: secondPageView.centerXAnchor),
            secondReloadButton.centerYAnchor.constraint(equalTo: secondPageView.centerYAnchor)
        ]
    }

    override func observe() {
        for key in [
            "Reader.disableDoubleTap",
            AppSettings.dictionary.enable.key,
            AppSettings.dictionary.lookupGesture.key,
            AppSettings.dictionary.restrictOCRLanguages.key,
            AppSettings.dictionary.restrictedOCRLanguages.key
        ] {
            addObserver(forName: key) { [weak self] _ in
                self?.updateDoubleTapZoomSetting()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        zoomView.updatePageSizing()
        updateBookSpine()
    }

    private func updateBookSpine() {
        let frames = [firstPageController, secondPageController].compactMap { controller -> CGRect? in
            guard let imageView = controller.pageView?.imageView, let image = imageView.image,
                  imageView.isDescendant(of: pageStack) else { return nil }
            let artwork = ReaderPageSizingGeometry.aspectFitFrame(imageSize: image.size, in: imageView.bounds)
            return imageView.convert(artwork, to: pageStack)
        }
        bookSpineView.update(pageFrames: frames, enabled: view.bounds.width > view.bounds.height)
        pageStack.bringSubviewToFront(bookSpineView)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard
            let firstPageView = firstPageController.pageView,
            let secondPageView = secondPageController.pageView
        else { return }

        // Fill Width can lock a single page above or below 1. Release those
        // limits before reparenting its view; the spread supplies one shared zoom.
        for controller in [firstPageController, secondPageController] {
            guard let childZoomView = controller.zoomView else { continue }
            childZoomView.minimumZoomScale = min(childZoomView.minimumZoomScale, 1)
            childZoomView.maximumZoomScale = max(childZoomView.maximumZoomScale, 1)
            childZoomView.setZoomScale(1, animated: false)
        }

        if
            !firstPageView.isDescendant(of: pageStack)
                || !secondPageView.isDescendant(of: pageStack)
        {
            for view in pageStack.arrangedSubviews {
                pageStack.removeArrangedSubview(view)
                view.removeFromSuperview()
            }

            for controller in [firstPageController, secondPageController] {
                NSLayoutConstraint.deactivate(controller.doublePageRestorationConstraints)
                controller.doublePageRestorationConstraints = []
                if let pageView = controller.pageView, pageView.superview !== pageStack {
                    pageView.removeFromSuperview()
                }
                controller.isInDoublePageController = true
            }

            let orderedViews = direction == .ltr
                ? [firstPageView, secondPageView]
                : [secondPageView, firstPageView]
            for view in orderedViews {
                pageStack.addArrangedSubview(view)
            }
        }
        NSLayoutConstraint.activate(pageLayoutConstraints)
        view.setNeedsLayout()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // A replaced pager can finish its disappearance after this same
        // spread is already visible in the new pager. Its artwork still
        // belongs here whenever the current parent displays this controller.
        if let pager = parent as? UIPageViewController,
           pager.viewControllers?.contains(where: { $0 === self }) == true {
            return
        }
        releasePageViews()
    }

    /// Release only artwork this wrapper still owns. The same canonical page
    /// controllers can then become independent native book leaves.
    func releasePageViews() {
        NSLayoutConstraint.deactivate(pageLayoutConstraints)
        for controller in [firstPageController, secondPageController] {
            guard
                let pageView = controller.pageView,
                let zoomView = controller.zoomView,
                pageView.isDescendant(of: pageStack)
            else { continue }
            controller.isInDoublePageController = false
            pageStack.removeArrangedSubview(pageView)
            pageView.removeFromSuperview()
            zoomView.addSubview(pageView)
            pageView.translatesAutoresizingMaskIntoConstraints = false
            let constraints = [
                pageView.topAnchor.constraint(equalTo: zoomView.contentLayoutGuide.topAnchor),
                pageView.leadingAnchor.constraint(equalTo: zoomView.contentLayoutGuide.leadingAnchor),
                pageView.trailingAnchor.constraint(equalTo: zoomView.contentLayoutGuide.trailingAnchor),
                pageView.bottomAnchor.constraint(equalTo: zoomView.contentLayoutGuide.bottomAnchor),
                pageView.widthAnchor.constraint(equalTo: zoomView.frameLayoutGuide.widthAnchor),
                pageView.heightAnchor.constraint(equalTo: zoomView.frameLayoutGuide.heightAnchor)
            ]
            NSLayoutConstraint.activate(constraints)
            controller.doublePageRestorationConstraints = constraints
        }
    }

    // TODO: fix `SWIFT TASK CONTINUATION MISUSE: setPageImage(url:sourceId:) leaked its continuation!`
    func setPage(_ page: Page, sourceId: String? = nil, for pos: ReaderPagedViewController.PagePosition) {
        let pageView: ReaderPageView?
        let reloadButton: UIButton
        switch pos {
            case .first:
                firstPageSet = true
                firstPage = page
                pageView = firstPageController.pageView
                reloadButton = firstReloadButton
            case .second:
                secondPageSet = true
                secondPage = page
                pageView = secondPageController.pageView
                reloadButton = secondReloadButton
        }
        guard let pageView = pageView else {
            return
        }
        updateDoubleTapZoomSetting()
        Task {
            let result = await pageView.setPage(page, sourceId: sourceId)
            if !result {
                if pos == .first {
                    firstPageSet = false
                } else {
                    secondPageSet = false
                }
                reloadButton.isHidden = false
            } else {
                reloadButton.isHidden = true
                view.layoutIfNeeded()
                zoomView.updatePageSizing(resetZoom: true)
                updateBookSpine()
            }
        }
    }

    @objc func reload(_ sender: UIButton) {
        if sender == firstReloadButton {
            guard let firstPageView = firstPageController.pageView else { return }
            firstReloadButton.isHidden = true
            firstPageView.progressView.setProgress(value: 0, withAnimation: false)
            firstPageView.progressView.isHidden = false
            if let firstPage = firstPage {
                setPage(firstPage, for: .first)
            }
        } else {
            guard let secondPageView = secondPageController.pageView else { return }
            secondReloadButton.isHidden = true
            secondPageView.progressView.setProgress(value: 0, withAnimation: false)
            secondPageView.progressView.isHidden = false
            if let secondPage = secondPage {
                setPage(secondPage, for: .second)
            }
        }
    }

    private func updateDoubleTapZoomSetting() {
        let disabled = AppSettings.dictionary.isReaderDoubleTapDisabled(language: firstPage?.language)
            && AppSettings.dictionary.isReaderDoubleTapDisabled(language: secondPage?.language)
        zoomView.doubleTapEnabled = !disabled
    }
}
