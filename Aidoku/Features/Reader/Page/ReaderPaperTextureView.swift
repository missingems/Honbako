//
//  ReaderPaperTextureView.swift
//  Aidoku
//

import UIKit

final class ReaderPaperTextureView: UIView {
    private var hasImage = false
    private var preferenceObservers: [NSObjectProtocol] = []
    private var renderedStrength: ReaderPaperTextureStrength?

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        isOpaque = false
        isHidden = true
        #if !SUMI
        for key in [AppSettings.reader.paperTexture.key, AppSettings.reader.paperTextureStrength.key] {
            let observer = NotificationCenter.default.addObserver(
                forName: .init(key), object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshVisibility() }
            }
            preferenceObservers.append(observer)
        }
        #endif
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        for observer in preferenceObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func update(imageSize: CGSize?, in imageBounds: CGRect, contentMode: UIView.ContentMode) {
        hasImage = imageSize.map { $0.width > 0 && $0.height > 0 } ?? false
        if let imageSize, contentMode == .scaleAspectFit {
            frame = ReaderPageSizingGeometry.aspectFitFrame(imageSize: imageSize, in: imageBounds)
        } else {
            frame = imageBounds
        }
        refreshVisibility()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.displayScale != traitCollection.displayScale {
            backgroundColor = nil
            refreshVisibility()
        }
    }

    private func refreshVisibility() {
        #if SUMI
        isHidden = !hasImage
        if backgroundColor == nil { backgroundColor = SumiPaperSurface.inkColor }
        #else
        isHidden = !hasImage || !AppSettings.reader.paperTexture.get()
        let strength = AppSettings.reader.paperTextureStrength.get()
        if !isHidden, backgroundColor == nil || renderedStrength != strength,
           let tile = ReaderPaperTexture.image(displayScale: traitCollection.displayScale, strength: strength) {
            backgroundColor = UIColor(patternImage: tile)
            renderedStrength = strength
        }
        #endif
    }
}
