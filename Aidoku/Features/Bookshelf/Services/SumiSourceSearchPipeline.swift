#if SUMI
import Foundation

/// Fetching another provider never waits for the previous provider's chapter
/// checks. Each prepared source can publish independently of slower sources.
enum SumiSourceSearchPipeline {
    private enum Event<Output: Sendable>: Sendable {
        case fetched(Output)
        case prepared
    }

    static func run<Output: Sendable>(
        sourceKeys: [String], maximumFetches: Int = 3,
        fetch: @escaping @Sendable (String) async -> Output,
        prepare: @escaping @Sendable (Output) async -> Void
    ) async {
        guard !Task.isCancelled else { return }
        await withTaskGroup(of: Event<Output>.self) { group in
            var next = 0
            for _ in 0..<min(max(1, maximumFetches), sourceKeys.count) {
                let key = sourceKeys[next]
                next += 1
                group.addTask { .fetched(await fetch(key)) }
            }
            while let event = await group.next() {
                guard !Task.isCancelled else { group.cancelAll(); return }
                switch event {
                case .fetched(let output):
                    if next < sourceKeys.count {
                        let key = sourceKeys[next]
                        next += 1
                        group.addTask { .fetched(await fetch(key)) }
                    }
                    group.addTask { await prepare(output); return .prepared }
                case .prepared:
                    break
                }
            }
        }
    }
}
#endif
