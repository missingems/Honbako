#if SUMI
import AidokuRunner
import UIKit

/// The inside back cover carries a normal, scrollable chapter index. It is a
/// physical reader leaf, so it participates in the same curl mesh as the art.
final class SumiIndexLeafViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    let index: SumiReaderIndex
    var onSelectChapter: ((AidokuRunner.Chapter) -> Void)?
    var bookBindingEdge: ReaderBookSpineView.BindingEdge = .none {
        didSet { if isViewLoaded { updatePaperShape() } }
    }
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let maskLayer = CAShapeLayer()

    init(index: SumiReaderIndex) {
        self.index = index
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        view.accessibilityIdentifier = "Sumi.Reader.Index.Container"
        table.accessibilityIdentifier = "Sumi.Reader.Index"
        let imprint = UILabel()
        imprint.text = [index.manga.title, index.manga.authors?.joined(separator: ", ")]
            .compactMap { $0 }.joined(separator: "\n\n")
        imprint.font = .preferredFont(forTextStyle: .body)
        imprint.adjustsFontForContentSizeCategory = true
        imprint.textColor = .label
        imprint.numberOfLines = 0
        imprint.alpha = 0.055
        imprint.isAccessibilityElement = false
        imprint.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imprint)
        table.dataSource = self
        table.delegate = self
        table.backgroundColor = .clear
        table.register(UITableViewCell.self, forCellReuseIdentifier: "chapter")
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 56
        table.contentInsetAdjustmentBehavior = .never
        // Curl leaves are manually sized to exact half-point viewports. Keep
        // the table on that same immediate geometry rather than waiting for a
        // separate Auto Layout pass before UIKit asks for its snapshot/AX tree.
        table.frame = view.bounds
        table.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        table.translatesAutoresizingMaskIntoConstraints = true
        view.addSubview(table)
        NSLayoutConstraint.activate([
            imprint.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            imprint.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            imprint.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            imprint.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -24)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        table.contentInset.top = max(12, view.safeAreaInsets.top)
        table.contentInset.bottom = max(12, view.safeAreaInsets.bottom)
        updatePaperShape()
    }

    func updatePaperShape() {
        if table.frame != view.bounds { table.frame = view.bounds }
        table.setNeedsLayout()
        table.layoutIfNeeded()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskLayer.frame = view.bounds
        maskLayer.path = ReaderBookSpineView.pagePath(in: view.bounds, bindingEdge: bookBindingEdge)
        view.layer.mask = maskLayer
        CATransaction.commit()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { index.readingOrder.count }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { "Chapters" }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = index.readingOrder[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "chapter", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = row.title
        content.secondaryText = row.subtitle
        content.textProperties.color = row.canRead ? .label : .secondaryLabel
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        cell.accessoryType = row.completed ? .checkmark : .none
        cell.selectionStyle = row.canRead ? .default : .none
        cell.isUserInteractionEnabled = row.canRead
        cell.accessibilityIdentifier = "Sumi.Reader.Index.Chapter.\(row.chapter.key)"
        if !row.canRead { cell.accessibilityTraits.insert(.notEnabled) }
        else { cell.accessibilityTraits.remove(.notEnabled) }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = index.readingOrder[indexPath.row]
        guard row.canRead else { return }
        onSelectChapter?(row.chapter)
    }
}
#endif
