//
//  TextDoublePageViewController.swift
//  Aidoku
//

import UIKit

class TextDoublePageViewController: UIViewController {
    enum Direction {
        case ltr
        case rtl
    }

    let leftPage: TextPage
    let rightPage: TextPage?
    let direction: Direction
    private let geometry: ReaderTextPageGeometry

    private lazy var stackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.distribution = .fillEqually
        sv.spacing = ReaderTextPageGeometry.spreadSpacing
        return sv
    }()

    private lazy var leftTextView: UITextView = createTextView()
    private lazy var rightTextView: UITextView = createTextView()
    private lazy var dividerView: UIView = {
        let v = UIView()
        v.backgroundColor = .separator
        return v
    }()

    init(leftPage: TextPage, rightPage: TextPage?, direction: Direction, geometry: ReaderTextPageGeometry) {
        self.leftPage = leftPage
        self.rightPage = rightPage
        self.direction = direction
        self.geometry = geometry
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = ReaderTextTheme.getCurrentBackground()

        view.addSubview(dividerView)
        dividerView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        if direction == .rtl {
            stackView.addArrangedSubview(rightTextView)
            stackView.addArrangedSubview(leftTextView)
            rightTextView.attributedText = rightPage?.attributedContent
            leftTextView.attributedText = leftPage.attributedContent
        } else {
            stackView.addArrangedSubview(leftTextView)
            stackView.addArrangedSubview(rightTextView)
            leftTextView.attributedText = leftPage.attributedContent
            rightTextView.attributedText = rightPage?.attributedContent
        }

        // Apply outer side insets to the spread once, preserving equal page widths
        // even when the camera or system controls occupy only one side.
        let outerInsets = geometry.spreadOuterInsets
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.topAnchor),
            stackView.leftAnchor.constraint(equalTo: view.leftAnchor, constant: outerInsets.left),
            stackView.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -outerInsets.right),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            dividerView.centerXAnchor.constraint(equalTo: stackView.centerXAnchor),
            dividerView.topAnchor.constraint(equalTo: stackView.topAnchor, constant: 20),
            dividerView.bottomAnchor.constraint(equalTo: stackView.bottomAnchor, constant: -20),
            dividerView.widthAnchor.constraint(equalToConstant: 1)
        ])

        updateTextInsets()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateTextInsets()
    }

    /// Position text using the same geometry snapshot used for pagination.
    private func updateTextInsets() {
        for textView in [leftTextView, rightTextView] {
            // UIStackView may round equal columns to different display pixels.
            // Absorb that difference into trailing padding so UITextView's own
            // container sizing preserves the paginator's exact wrapping width.
            var insets = geometry.textInsets
            if textView.bounds.width > 0 {
                insets.right += textView.bounds.width - geometry.pageSize.width
            }
            if textView.textContainerInset != insets {
                textView.textContainerInset = insets
                textView.layoutIfNeeded()
            }
        }
    }

    private func createTextView() -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isScrollEnabled = false
        tv.isUserInteractionEnabled = false  // Let taps pass through to parent tap zones
        tv.textContainer.lineFragmentPadding = 0  // Match paginator's layout width
        tv.backgroundColor = ReaderTextTheme.getCurrentBackground()
        return tv
    }
}
