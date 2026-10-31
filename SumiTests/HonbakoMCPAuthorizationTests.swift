@testable import Sumi
import Foundation
import Testing

struct HonbakoMCPAuthorizationTests {
    @Test("Consent lookup waits for a deep-linked app to finish activating")
    @MainActor
    func foregroundTransition() async throws {
        var observations = 0
        try await HonbakoMCPAuthorizationGate.waitUntilActive(interval: .milliseconds(1)) {
            observations += 1
            return observations == 3
        }
        #expect(observations == 3)
    }

    @Test("An already active app does not delay consent lookup")
    @MainActor
    func alreadyActive() async throws {
        var observations = 0
        try await HonbakoMCPAuthorizationGate.waitUntilActive(timeout: .zero) {
            observations += 1
            return true
        }
        #expect(observations == 1)
    }

    @Test("An app that never activates offers retry instead of reporting an expired request")
    @MainActor
    func inactiveTimeout() async {
        do {
            try await HonbakoMCPAuthorizationGate.waitUntilActive(timeout: .milliseconds(3), interval: .milliseconds(1)) { false }
            Issue.record("Inactive consent lookup must not proceed")
        } catch {
            #expect(error as? HonbakoMCPAuthorizationError == .inactive)
            #expect(HonbakoMCPAuthorizationError.inactive.canRetry)
        }
    }

    @Test("Closing consent cancels its activation wait and never proceeds to authorization")
    @MainActor
    func cancellation() async {
        let wait = Task { @MainActor in
            try await HonbakoMCPAuthorizationGate.waitUntilActive { false }
        }
        wait.cancel()
        do {
            try await wait.value
            Issue.record("Cancelled consent must not proceed")
        } catch {
            #expect(error is CancellationError)
        }
    }

    @Test("Only expired or answered requests ask for a new AI connection")
    func failureRecovery() {
        for status in [400, 410] {
            #expect(HonbakoMCPAuthorizationError.response(status: status) == .requestExpired)
            #expect(!HonbakoMCPAuthorizationError.response(status: status).canRetry)
        }
        for status in [401, 403] {
            #expect(HonbakoMCPAuthorizationError.response(status: status) == .connectionRequired)
        }
        #expect(HonbakoMCPAuthorizationError.response(status: 402) == .proRequired)
        for status in [404, 409, 429, 500, 502, 503] {
            #expect(HonbakoMCPAuthorizationError.response(status: status) == .unavailable)
            #expect(HonbakoMCPAuthorizationError.response(status: status).canRetry)
        }
        #expect(HonbakoMCPAuthorizationError.proRequired.errorDescription?.contains("Restore Purchases") == true)
    }
}
