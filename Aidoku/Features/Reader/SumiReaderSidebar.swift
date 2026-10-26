#if SUMI
import AidokuRunner
import UIKit

/// One native list gives headings, fit options, and chapters a shared text edge.
final class SumiReaderSidebar: UITableView, UITableViewDataSource, UITableViewDelegate {
    var onSizing: ((ReaderPageSizing) -> Void)?
    var onChapter: ((AidokuRunner.Chapter) -> Void)?
    var isChapterReadable: ((AidokuRunner.Chapter) -> Bool)?
    private var chapters: [AidokuRunner.Chapter] = []
    private var currentChapterKey = ""
    private var sizing: ReaderPageSizing = .fit
    private static let rowID = "Sumi.Reader.Sidebar.Row"
    private static let headerID = "Sumi.Reader.Sidebar.Header"

    init() {
        super.init(frame: .zero, style: .plain)
        accessibilityIdentifier = "Sumi.Reader.Sidebar"
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 22
        clipsToBounds = true
        dataSource = self
        delegate = self
        rowHeight = UITableView.automaticDimension
        estimatedRowHeight = 52
        sectionHeaderHeight = UITableView.automaticDimension
        estimatedSectionHeaderHeight = 40
        sectionHeaderTopPadding = 0
        contentInsetAdjustmentBehavior = .never
        insetsContentViewsToSafeArea = false
        directionalLayoutMargins = .zero
        separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        register(UITableViewCell.self, forCellReuseIdentifier: Self.rowID)
        register(UITableViewHeaderFooterView.self, forHeaderFooterViewReuseIdentifier: Self.headerID)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(chapters: [AidokuRunner.Chapter], chapterKey: String, sizing: ReaderPageSizing) {
        self.chapters = Array(chapters.reversed())
        currentChapterKey = chapterKey
        self.sizing = sizing
        reloadData()
    }

    func numberOfSections(in tableView: UITableView) -> Int { 2 }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 2 : chapters.count
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header = dequeueReusableHeaderFooterView(withIdentifier: Self.headerID)
            ?? UITableViewHeaderFooterView(reuseIdentifier: Self.headerID)
        var content = UIListContentConfiguration.plainHeader()
        content.text = section == 0 ? "Page fit" : "Chapters"
        content.textProperties.font = .preferredFont(forTextStyle: .footnote)
        content.textProperties.color = .secondaryLabel
        content.textProperties.numberOfLines = 0
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16)
        header.contentConfiguration = content
        var background = UIBackgroundConfiguration.clear()
        background.backgroundColor = .secondarySystemBackground
        header.backgroundConfiguration = background
        header.preservesSuperviewLayoutMargins = false
        header.directionalLayoutMargins = .zero
        return header
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = dequeueReusableCell(withIdentifier: Self.rowID, for: indexPath)
        cell.backgroundColor = .secondarySystemBackground
        cell.preservesSuperviewLayoutMargins = false
        cell.directionalLayoutMargins = .zero
        cell.accessoryType = .none
        var content = UIListContentConfiguration.cell()
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 12)
        content.textProperties.font = .preferredFont(forTextStyle: .body)
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 0
        if indexPath.section == 0 {
            let choice: ReaderPageSizing = indexPath.row == 0 ? .fit : .fill
            content.text = choice == .fit ? "Fit to Page" : "Fill Page"
            cell.accessoryType = sizing == choice ? .checkmark : .none
            cell.accessibilityIdentifier = choice == .fit ? "Sumi.Reader.FitPage" : "Sumi.Reader.FillPage"
            cell.accessibilityTraits = sizing == choice ? [.button, .selected] : .button
        } else {
            let chapter = chapters[indexPath.row]
            let title = Self.title(for: chapter)
            content.text = title
            if let subtitle = chapter.title?.trimmingCharacters(in: .whitespacesAndNewlines),
               !subtitle.isEmpty, subtitle.localizedCaseInsensitiveCompare(title) != .orderedSame {
                content.secondaryText = subtitle
            }
            cell.accessoryType = chapter.key == currentChapterKey ? .checkmark : .none
            cell.accessibilityIdentifier = "Sumi.Reader.Chapter.\(chapter.key)"
            cell.accessibilityTraits = chapter.key == currentChapterKey ? [.button, .selected] : .button
            if !(isChapterReadable?(chapter) ?? !chapter.locked) {
                // Keep the text edge fixed even for unavailable chapters.
                cell.accessoryView = UIImageView(image: UIImage(systemName: "lock"))
                content.textProperties.color = .secondaryLabel
                cell.accessibilityTraits.insert(.notEnabled)
            } else { cell.accessoryView = nil }
        }
        if indexPath.section == 0 { cell.accessoryView = nil }
        cell.contentConfiguration = content
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            sizing = indexPath.row == 0 ? .fit : .fill
            onSizing?(sizing)
            reloadSections(IndexSet(integer: 0), with: .none)
        } else {
            let chapter = chapters[indexPath.row]
            guard isChapterReadable?(chapter) ?? !chapter.locked else { return }
            onChapter?(chapter)
        }
    }

    private static func title(for chapter: AidokuRunner.Chapter) -> String {
        if let number = chapter.chapterNumber { return "Chapter \(String(format: "%g", Double(number)))" }
        return chapter.title ?? "Chapter"
    }
}
#endif
