#if SUMI
import Foundation

enum HonbakoPageCoachingPolicy {
    typealias Models = HonbakoPageCoachingModels
    static let lifetime: TimeInterval = 600
    static let maximumImageBytes = 350 * 1024

    @MainActor
    static func validCapture(_ capture: HonbakoPageCoachingCapture) -> Bool {
        HonbakoAutomationPolicy.validItem(.init(sourceId: capture.sourceId, mangaId: capture.mangaId))
            && HonbakoAutomationPolicy.exportableIdentifier(capture.chapterId)
            && !capture.chapterId.isEmpty && capture.chapterId.utf8.count <= 2048
            && capture.chapterId.rangeOfCharacter(from: .controlCharacters) == nil
            && capture.page.type == .imagePage && !capture.page.isTextPage
            && capture.page.sourceId == capture.sourceId && capture.page.chapterId == capture.chapterId
            && capture.canonicalPage >= 1 && capture.canonicalPage <= 1_000_000
            && (capture.totalPages.map { $0 >= capture.canonicalPage && $0 <= 1_000_000 } ?? true)
            && (capture.lastVisiblePage.map { $0 >= capture.canonicalPage && $0 <= (capture.totalPages ?? 1_000_000) } ?? true)
            && (capture.chapterNumber.map(\.isFinite) ?? true)
    }

    static func valid(_ annotation: Models.Annotation) -> Bool {
        guard !annotation.id.isEmpty, annotation.id.utf8.count <= 64,
              annotation.id.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "_" || $0 == "-"
              }) else { return false }
        switch annotation.type {
        case .box:
            return annotation.rect.map(valid) == true && annotation.text == nil && annotation.points == nil
                && annotation.from == nil && annotation.to == nil
        case .arrow:
            return annotation.from.map(valid) == true && annotation.to.map(valid) == true
                && annotation.from != annotation.to && annotation.rect == nil
                && annotation.text == nil && annotation.points == nil
        case .label:
            return annotation.rect.map(valid) == true && annotation.text.map {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 280
                    && !$0.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t" }
            } == true && annotation.from == nil && annotation.to == nil && annotation.points == nil
        case .stroke:
            return annotation.points.map { (2...128).contains($0.count) && $0.allSatisfy(valid) } == true
                && annotation.rect == nil && annotation.text == nil && annotation.from == nil && annotation.to == nil
        }
    }
    static func valid(_ point: Models.Point) -> Bool {
        point.x.isFinite && point.y.isFinite && (0...1).contains(point.x) && (0...1).contains(point.y)
    }
    static func valid(_ rect: Models.Rect) -> Bool {
        valid(Models.Point(x: rect.x, y: rect.y)) && rect.width.isFinite && rect.height.isFinite
            && rect.width > 0 && rect.height > 0 && rect.x + rect.width <= 1 && rect.y + rect.height <= 1
    }
    static func accepts(_ state: Models.State, for page: Models.PageReference, after revision: Int, now: Date) -> Bool {
        guard state.active, state.sessionId == page.sessionId, state.pageId == page.pageId,
              state.contentHash == page.contentHash, state.pageGeneration == page.pageGeneration,
              (state.accessMode == "connection" ? state.expiresAt == nil
                : state.accessMode == nil && state.expiresAt.flatMap(date).map { $0 > now } == true),
              state.annotationRevision > revision, state.annotations.count <= 24,
              Set(state.annotations.map(\.id)).count == state.annotations.count else { return false }
        return state.annotations.allSatisfy(valid)
    }
    static func timestamp(_ date: Date) -> String {
        date.ISO8601Format(.init(includingFractionalSeconds: true))
    }
    static func date(_ value: String) -> Date? {
        (try? Date(value, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .colon)))
            ?? (try? Date(value, strategy: .iso8601))
    }
}
#endif
