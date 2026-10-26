//
//  ReaderPageSizingGeometry.swift
//  Aidoku
//

import CoreGraphics

struct ReaderPageSizingGeometry: Equatable {
    let viewportSize: CGSize
    let contentSize: CGSize
    let pageFrame: CGRect

    static func aspectFitFrame(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }

    init?(viewportSize: CGSize, contentSize: CGSize, pageFrame: CGRect) {
        guard
            viewportSize.width > 0, viewportSize.height > 0,
            contentSize.width > 0, contentSize.height > 0,
            pageFrame.width > 0, pageFrame.height > 0,
            [viewportSize.width, viewportSize.height, contentSize.width, contentSize.height,
             pageFrame.width, pageFrame.height].allSatisfy(\.isFinite)
        else { return nil }
        self.viewportSize = viewportSize
        self.contentSize = contentSize
        self.pageFrame = pageFrame
    }

    func baselineScale(for sizing: ReaderPageSizing) -> CGFloat {
        switch sizing {
            case .fit: 1
            case .fill: viewportSize.width / pageFrame.width
        }
    }
}
