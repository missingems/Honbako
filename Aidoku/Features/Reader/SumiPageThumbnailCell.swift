#if SUMI
import UIKit

final class SumiPageThumbnailCell: UICollectionViewCell {
    static let reuseID = "Sumi.PageThumbnail"
    private let thumbnail = SumiSpreadThumbnailView()
    private(set) var group = 0
    private(set) var previewReady = false
    var onPreviewReady: ((Bool) -> Void)?
    private var paired = false
    var isVertical = false { didSet { if isVertical != oldValue { setNeedsLayout() } } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(thumbnail)
        isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        let count: CGFloat = paired ? 2 : 1
        let preferredHeight = SumiScrubberMetrics.pageHeight
        let preferredWidth = preferredHeight * SumiScrubberMetrics.pageAspect * count
        // In a side rail the native collection rotates as a whole. The print
        // rotates back, so its upright width must fit the cell's cross axis.
        let availableWidth = isVertical ? contentView.bounds.height : contentView.bounds.width - 4
        let availableHeight = isVertical ? contentView.bounds.width - 4 : contentView.bounds.height
        let scale = min(1, availableWidth / preferredWidth, availableHeight / preferredHeight)
        let width = preferredWidth * max(0, scale)
        let height = preferredHeight * max(0, scale)
        thumbnail.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        thumbnail.center = CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        // The rail turns as one native scroll view; keep printed pages upright.
        thumbnail.transform = isVertical ? CGAffineTransform(rotationAngle: -.pi / 2) : .identity
    }
    override func prepareForReuse() {
        super.prepareForReuse(); thumbnail.cancelImage(clear: true); contentView.alpha = 1; previewReady = false
    }
    func configure(chapterKey: String = "", group: Int, pages: [Int], reversed: Bool, provider: ((Int) async -> UIImage?)?) {
        self.group = group
        paired = pages.count > 1
        previewReady = false
        let first = pages.first ?? 1
        accessibilityIdentifier = pages.count == 1 ? "Sumi.Reader.Thumbnail.\(first)" : "Sumi.Reader.Spread.\(first)-\(pages.last ?? first)"
        accessibilityLabel = pages.count == 1 ? "Page \(first)" : "Pages \(first) and \(pages.last ?? first)"
        accessibilityValue = "Loading preview"
        accessibilityTraits = .button
        thumbnail.configure(identity: chapterKey, pages: pages, reversed: reversed, provider: provider) { [weak self] ready in
            guard self?.group == group else { return }
            self?.accessibilityValue = ready ? "Preview ready" : "Preview unavailable"
            self?.previewReady = ready
            self?.onPreviewReady?(ready)
        }
        setNeedsLayout()
    }
    func updateSelection(_ selected: Bool) {
        contentView.alpha = 1
        contentView.transform = .identity
        accessibilityTraits = selected ? [.button, .selected] : .button
    }
    func cancelImage() { thumbnail.cancelImage() }
}
#endif
