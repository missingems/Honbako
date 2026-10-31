#if SUMI
import AidokuRunner
import Combine
import Foundation

/// Session knowledge from actual page-list requests. A connection failure is
/// never evidence that a chapter is missing. Source instances and manga IDs
/// isolate accounts and books that happen to reuse the same chapter identifier.
@MainActor
final class HonbakoChapterAvailability: ObservableObject {
    enum State: Equatable, Sendable { case unknown, available, unavailable }
    private struct Entry { let state: State; let expires: Date }
    static let shared = HonbakoChapterAvailability(observeSourceChanges: true)
    @Published private(set) var revision = 0
    private var entries: [SumiChapterPageListCache.Key: Entry] = [:]
    private var observers: [NSObjectProtocol] = []

    init(observeSourceChanges: Bool = false) {
        if observeSourceChanges {
            for name in [Notification.Name.sourceLoaded, .sourceUnloaded] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    guard let sourceKey = note.object as? String else { return }
                    Task { @MainActor [weak self] in self?.clear(sourceKey: sourceKey) }
                })
            }
        }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func clear(sourceKey: String) {
        let before = entries.count
        entries = entries.filter { $0.key.sourceKey != sourceKey }
        if before != entries.count { revision &+= 1 }
    }

    func state(for key: SumiChapterPageListCache.Key, now: Date = .now) -> State {
        guard let entry = entries[key], entry.expires > now else { return .unknown }
        return entry.state
    }

    func record(_ state: State, for key: SumiChapterPageListCache.Key, expires: Date) {
        entries[key] = Entry(state: state, expires: expires)
        if entries.count > 512, let oldest = entries.min(by: { $0.value.expires < $1.value.expires })?.key {
            entries[oldest] = nil
        }
        revision &+= 1
    }

    func clear(_ key: SumiChapterPageListCache.Key) {
        if entries.removeValue(forKey: key) != nil { revision &+= 1 }
    }

    func clear(sourceKey: String, mangaKey: String) {
        let before = entries.count
        entries = entries.filter { $0.key.sourceKey != sourceKey || $0.key.mangaKey != mangaKey }
        if before != entries.count { revision &+= 1 }
    }

    func isUnavailable(source: AidokuRunner.Source, manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter) -> Bool {
        state(for: .init(source: source, manga: manga, chapter: chapter)) == .unavailable
    }

    nonisolated static func confirmsUnavailable(_ error: Error) -> Bool {
        guard let error = error as? HonbakoMangaDexError else { return false }
        return switch error {
        case .unavailableChapter, .requestFailed(404), .requestFailed(410): true
        default: false
        }
    }
}
#endif
