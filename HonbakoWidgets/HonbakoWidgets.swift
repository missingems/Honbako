import SwiftUI
import WidgetKit

@main
struct HonbakoWidgets: WidgetBundle {
    var body: some Widget {
        HonbakoResumeWidget()
        HonbakoReadingTimeWidget()
        HonbakoChapterUpdatesWidget()
    }
}
