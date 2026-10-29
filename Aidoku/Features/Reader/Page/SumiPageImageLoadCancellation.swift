#if SUMI
import Foundation
import Nuke

/// Leaving a preload range is normal reader behavior, not a connection error.
enum SumiPageImageLoadCancellation {
    static func contains(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let error = error as? URLError, error.code == .cancelled { return true }
        if let error = error as? ImagePipeline.Error {
            switch error {
            case .cancelled: return true
            case .dataLoadingFailed(let underlying): return contains(underlying)
            default: return false
            }
        }
        return false
    }
}
#endif
