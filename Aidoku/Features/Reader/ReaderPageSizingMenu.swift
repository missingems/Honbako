//
//  ReaderPageSizingMenu.swift
//  Aidoku
//

import UIKit

enum ReaderPageSizingMenu {
    static func makeMenu() -> UIMenu {
        let selected = AppSettings.reader.pageSizing.get()
        let actions = ReaderPageSizing.allCases.map { sizing in
            UIAction(
                title: sizing.title,
                image: UIImage(systemName: sizing == .fit ? "arrow.down.right.and.arrow.up.left" : "arrow.left.and.right"),
                state: selected == sizing ? .on : .off
            ) { _ in
                AppSettings.reader.pageSizing.set(sizing)
                // Reselecting Fit Screen also resets a manually zoomed page.
                NotificationCenter.default.post(name: .init(AppSettings.reader.pageSizing.key), object: nil)
            }
        }
        return UIMenu(title: NSLocalizedString("PAGE_SIZING"), options: .singleSelection, children: actions)
    }
}
