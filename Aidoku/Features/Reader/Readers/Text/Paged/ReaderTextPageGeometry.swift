//
//  ReaderTextPageGeometry.swift
//  Aidoku
//

import UIKit

/// Shared geometry keeps the paginator and its text views at exactly the same size.
struct ReaderTextPageGeometry: Equatable {
    static let spreadSpacing: CGFloat = 1

    let pageSize: CGSize
    let textInsets: UIEdgeInsets
    let spreadOuterInsets: UIEdgeInsets

    init(size: CGSize, safeAreaInsets: UIEdgeInsets, usesDoublePages: Bool, config: PaginationConfig) {
        let toolbarBuffer: CGFloat = 100
        let safeWidth = size.width - safeAreaInsets.left - safeAreaInsets.right
        pageSize = CGSize(
            width: usesDoublePages ? (safeWidth - Self.spreadSpacing) / 2 : safeWidth,
            height: size.height - safeAreaInsets.top - safeAreaInsets.bottom - toolbarBuffer
        )

        // The spread container consumes the outer side insets once. Each child
        // then needs only its own text padding, including at the inner gutter.
        spreadOuterInsets = UIEdgeInsets(top: 0, left: safeAreaInsets.left, bottom: 0, right: safeAreaInsets.right)
        textInsets = UIEdgeInsets(
            top: safeAreaInsets.top + toolbarBuffer / 2 + config.verticalPadding,
            left: (usesDoublePages ? 0 : safeAreaInsets.left) + config.horizontalPadding,
            bottom: safeAreaInsets.bottom + toolbarBuffer / 2 + config.verticalPadding,
            right: (usesDoublePages ? 0 : safeAreaInsets.right) + config.horizontalPadding
        )
    }
}
