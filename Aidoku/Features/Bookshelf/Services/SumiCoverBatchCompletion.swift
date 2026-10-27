#if SUMI
/// A one-shot UI waiter. The presentation deadline can finish its wait while
/// the loader's separate bounded cohort continues preparing its publication.
@MainActor
final class SumiCoverBatchCompletion {
    private var finished = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        if finished { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func finish() {
        guard !finished else { return }
        finished = true
        continuation?.resume()
        continuation = nil
    }
}
#endif
