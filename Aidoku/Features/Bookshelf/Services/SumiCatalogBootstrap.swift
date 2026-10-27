#if SUMI
import Combine
import Foundation

/// Loads only sources the reader has already added. Sumi never installs a
/// package, adds a source list, or contacts a catalog during first launch.
@MainActor
final class SumiCatalogBootstrap: ObservableObject {
    static let shared = SumiCatalogBootstrap()

    enum State: Equatable { case idle, preparing, ready, failed(String) }
    typealias SourceLoader = @MainActor @Sendable () async -> [String]
    @Published private(set) var state: State = .idle
    @Published private(set) var availableSourceKeys: [String] = []
    @Published private(set) var failures: [String: String] = [:]
    private let sourceLoader: SourceLoader
    private var preparation: Task<Void, Never>?

    init(sourceLoader: SourceLoader? = nil) {
        self.sourceLoader = sourceLoader ?? {
            await SourceManager.shared.waitForSourcesLoad()
            return await SourceManager.shared.getLoadedSources().map(\.key)
        }
    }

    func prepare() async {
        if let preparation { await preparation.value; return }
        state = .preparing
        let task = Task {
            availableSourceKeys = await sourceLoader().sorted()
            state = .ready
        }
        preparation = task
        await task.value
        preparation = nil
    }
}
#endif
