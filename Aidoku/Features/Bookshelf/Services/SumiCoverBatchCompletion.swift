#if SUMI
/// An unstructured worker can be cancelled at the deadline without waiting on
/// a provider that ignores cancellation. It cannot publish after the batch ends.
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
