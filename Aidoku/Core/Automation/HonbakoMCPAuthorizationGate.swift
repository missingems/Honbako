#if SUMI
import Foundation

/// Deep links arrive while iOS is still activating the app. Keep the transport's
/// foreground-only rule, but let that transition complete before checking consent.
enum HonbakoMCPAuthorizationGate {
    @MainActor
    static func waitUntilActive(timeout: Duration = .seconds(5), interval: Duration = .milliseconds(50),
                                isActive: @MainActor () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while true {
            try Task.checkCancellation()
            if isActive() { return }
            guard clock.now < deadline else { throw HonbakoMCPAuthorizationError.inactive }
            try await clock.sleep(until: min(clock.now.advanced(by: interval), deadline))
        }
    }
}
#endif
