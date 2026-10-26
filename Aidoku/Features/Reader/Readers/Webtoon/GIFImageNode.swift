//
//  GIFImageNode.swift
//  Aidoku
//
//  Created by Skitty on 6/23/25.
//

import AsyncDisplayKit
import Gifu
import VisionKit

class GIFImageNode: ASControlNode {
    var imageView: GIFImageView?
    private var paperTextureView: ReaderPaperTextureView?
    var animatedData: Data?
    var storedInteractions: [UIInteraction] = []

    override var contentMode: UIView.ContentMode {
        didSet {
            imageView?.contentMode = contentMode
            Task { @MainActor [weak self] in self?.updatePaperTexture() }
        }
    }

    var image: UIImage? {
        didSet {
            Task { @MainActor in
                imageView?.image = image
                updatePaperTexture()
            }
        }
    }

    override var isUserInteractionEnabled: Bool {
        didSet {
            imageView?.isUserInteractionEnabled = isUserInteractionEnabled
        }
    }

    @available(iOS 16.0, *)
    var imageAnalaysisInteraction: ImageAnalysisInteraction? {
        imageView?.interactions.first(where: { $0 is ImageAnalysisInteraction }) as? ImageAnalysisInteraction
    }

    override init() {
        super.init()

        setViewBlock { [weak self] in
            let gifView = GIFImageView()
            gifView.image = self?.image
            gifView.isUserInteractionEnabled = true
            if let contentMode = self?.contentMode {
                gifView.contentMode = contentMode
            }
            if let data = self?.animatedData {
                gifView.animate(withGIFData: data)
                self?.animatedData = nil
            }
            if let storedInteractions = self?.storedInteractions {
                storedInteractions.forEach {
                    gifView.addInteraction($0)
                }
                self?.storedInteractions = []
            }
            self?.imageView = gifView
            MainActor.assumeIsolated {
                let texture = ReaderPaperTextureView()
                texture.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                gifView.addSubview(texture)
                self?.paperTextureView = texture
                self?.updatePaperTexture()
            }
            return gifView
        }
    }

    override func layout() {
        super.layout()
        Task { @MainActor [weak self] in self?.updatePaperTexture() }
    }

    @MainActor
    private func updatePaperTexture() {
        guard let imageView else { return }
        paperTextureView?.update(imageSize: image?.size, in: imageView.bounds, contentMode: imageView.contentMode)
    }

    func animate(withGIFData data: Data) {
        if let imageView {
            Task { @MainActor in
                imageView.animate(withGIFData: data)
            }
        } else {
            animatedData = data
        }
    }

    func reset() {
        image = nil
        animatedData = nil

        Task { @MainActor [weak imageView] in
            imageView?.stopAnimatingGIF()
            imageView?.image = nil
        }
    }

    @MainActor
    func addInteraction(_ interaction: UIInteraction) {
        if let imageView {
            imageView.addInteraction(interaction)
        } else {
            storedInteractions.append(interaction)
        }
    }

    @MainActor
    @available(iOS 16.0, *)
    func removeImageAnalysisInteraction() {
        guard
            let imageView,
            let interaction = imageView.interactions.first(where: { $0 is ImageAnalysisInteraction })
        else {
            return
        }
        imageView.removeInteraction(interaction)
    }
}
