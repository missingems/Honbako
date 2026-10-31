#if SUMI
import Foundation
import Nuke
import NukeUI

/// NukeUI owns the request lifecycle while the reader keeps its native image
/// surface for zoom, animated artwork, page turns and overlays.
@MainActor
final class SumiPageImageFetch {
    private let pipeline: ImagePipeline
    private var image: FetchImage?
    private var identity: UUID?
    private var imageTask: ImageTask?
    private var continuation: CheckedContinuation<Result<ImageResponse, ImagePipeline.Error>, Never>?
    var isLoading: Bool { identity != nil }

    init(pipeline: ImagePipeline = .shared) { self.pipeline = pipeline }

    func response(for request: ImageRequest,
                  onStart: (@MainActor @Sendable (ImageTask) -> Void)? = nil) async throws(ImagePipeline.Error) -> ImageResponse {
        let id = UUID()
        let result: Result<ImageResponse, ImagePipeline.Error> = await withTaskCancellationHandler {
            guard !Task.isCancelled else { return .failure(.cancelled) }
            return await withCheckedContinuation { continuation in
                cancel()
                guard !Task.isCancelled else {
                    continuation.resume(returning: .failure(.cancelled))
                    return
                }
                self.identity = id
                self.continuation = continuation
                let image = FetchImage()
                image.pipeline = pipeline
                image.onStart = { [weak self] task in
                    guard let self, identity == id else { task.cancel(); return }
                    imageTask = task
                    onStart?(task)
                }
                image.onCompletion = { [weak self] result in
                    self?.finish(result.mapError { ($0 as? ImagePipeline.Error) ?? .dataLoadingFailed(error: $0) }, identity: id)
                }
                self.image = image
                image.load(request)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(identity: id) }
        }
        return try result.get()
    }

    func cancel() { cancel(identity: nil) }

    /// Texture can report preload exit off the main actor. Its eventual
    /// cancellation must affect the captured request, never a newer retry.
    func cancel(task: ImageTask) {
        guard imageTask === task else { return }
        cancel()
    }

    private func cancel(identity expected: UUID?) {
        guard expected == nil || expected == identity else { return }
        let pending = continuation
        continuation = nil
        identity = nil
        imageTask = nil
        image?.onCompletion = nil
        image?.onStart = nil
        image?.reset()
        image = nil
        // NukeUI cancellation does not call onCompletion. Resume the awaiting
        // reader explicitly so leaving a preload range cannot strand a task.
        pending?.resume(returning: .failure(.cancelled))
    }

    private func finish(_ result: Result<ImageResponse, ImagePipeline.Error>, identity expected: UUID) {
        guard identity == expected else { return }
        let pending = continuation
        continuation = nil
        identity = nil
        imageTask = nil
        image?.onCompletion = nil
        image?.onStart = nil
        image = nil
        pending?.resume(returning: result)
    }
}
#endif
