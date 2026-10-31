@testable import Sumi
import Foundation
import Testing

@MainActor
@Suite struct HonbakoAutomationEndpointMigrationTests {
    private typealias Models = HonbakoAutomationModels
    private let previous = Models.Connection(endpoint: URL(string: "http://192.168.1.22:43187")!,
        deviceId: "paired-device-1", deviceToken: String(repeating: "a", count: 64))

    @Test("A hosted move rejects insecure or credential-bearing addresses before probing")
    func invalidAddressesNeverReceiveTheDeviceCredential() async {
        for address in ["http://bridge.example.com", "http://192.168.1.22:43187", "https://user:secret@bridge.example.com",
                        "https://bridge.example.com?token=secret", "https://bridge.example.com#secret",
                        "https://bridge.example.com/api/%2e%2e/admin", "not an address"] {
            var probes = 0
            await #expect(throws: (any Error).self) {
                try await HonbakoAutomationService.prepareEndpointMove(to: address, from: previous) { _, _ in
                    probes += 1
                    return Data(#"{"jobs":[]}"#.utf8)
                }
            }
            #expect(probes == 0)
        }
    }

    @Test("A verified move keeps the exact device identity and accepts the existing pending approval")
    func preservesThePairingAndPendingPayload() async throws {
        let pending = job()
        let remote = job(status: "awaitingApproval")
        var probes = 0
        let moved = try await HonbakoAutomationService.prepareEndpointMove(
            to: "HTTPS://BRIDGE.EXAMPLE.COM/honbako/", from: previous, pendingJobs: [pending]
        ) { endpoint, token in
            probes += 1
            #expect(endpoint.absoluteString == "https://bridge.example.com/honbako")
            #expect(token == previous.deviceToken)
            return try response([remote])
        }
        #expect(probes == 1)
        #expect(moved.endpoint.absoluteString == "https://bridge.example.com/honbako")
        #expect(moved.deviceId == previous.deviceId)
        #expect(moved.deviceToken == previous.deviceToken)
        #expect(previous.endpoint.absoluteString == "http://192.168.1.22:43187")
    }

    @Test("A missing or changed pending addition blocks migration")
    func rejectsLostOrChangedPendingApprovals() async throws {
        let pending = job()
        let changed = job(mangaId: "different-book")
        for jobs in [[], [changed]] {
            await #expect(throws: (any Error).self) {
                try await HonbakoAutomationService.prepareEndpointMove(
                    to: "https://bridge.example.com", from: previous, pendingJobs: [pending]
                ) { _, _ in try response(jobs) }
            }
        }
    }

    @Test("A failed authentication probe never yields replacement credentials")
    func failedProbeLeavesTheOriginalConnectionAvailable() async {
        await #expect(throws: ProbeFailure.self) {
            try await HonbakoAutomationService.prepareEndpointMove(to: "https://bridge.example.com", from: previous) { _, _ in
                throw ProbeFailure.denied
            }
        }
        #expect(previous.endpoint.absoluteString == "http://192.168.1.22:43187")
        #expect(previous.deviceId == "paired-device-1")
    }

    @Test("Malformed, duplicate, oversized or unsupported queues cannot validate a destination")
    func rejectsInvalidProbeEnvelopes() async throws {
        let invalidAction = Models.Job(id: "pending-first", kind: "library.remove", payload: .init(),
            status: "queued", createdAt: "2026-10-29T10:00:00Z")
        for data in [Data(#"{}"#.utf8), Data(#"{"jobs":null}"#.utf8),
                     try response([job(), job()]), try response([invalidAction]),
                     try response((0..<101).map { job(id: "pending-\($0)") }), Data(count: 1_048_577)] {
            await #expect(throws: (any Error).self) {
                try await HonbakoAutomationService.prepareEndpointMove(to: "https://bridge.example.com", from: previous) { _, _ in data }
            }
        }
    }

    @Test("A cancelled probe cannot return a connection even if its response arrives successfully")
    func rejectsLateCancelledResponses() async {
        let previous = self.previous
        let attempt = Task {
            try await HonbakoAutomationService.prepareEndpointMove(to: "https://bridge.example.com", from: previous) { _, _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return Data(#"{"jobs":[]}"#.utf8)
            }
        }
        await #expect(throws: CancellationError.self) { try await attempt.value }
    }

    @Test("Move errors explain transport failures without exposing server bodies, URLs or credentials")
    func sanitizedMoveErrors() {
        let timedOut = HonbakoAutomationService.endpointMoveFailureMessage(for: URLError(.timedOut))
        #expect(timedOut.contains("timed out"))
        let network = HonbakoAutomationService.endpointMoveFailureMessage(for: URLError(.cannotFindHost))
        #expect(network.contains("-1003"))
        let secret = NSError(domain: "private", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bearer private-key-never-display"])
        let generic = HonbakoAutomationService.endpointMoveFailureMessage(for: secret)
        #expect(!generic.contains("private-key"))
        #expect(generic.contains("unchanged"))
    }

    private func job(id: String = "pending-first", status: String = "queued", mangaId: String = "first-book") -> Models.Job {
        .init(id: id, kind: "library.add",
            payload: .init(items: [.init(sourceId: "honbako.mangadex", mangaId: mangaId)], idempotencyKey: "existing-batch"),
            status: status, createdAt: "2026-10-29T10:00:00Z")
    }

    private func response(_ jobs: [Models.Job]) throws -> Data {
        try JSONEncoder().encode(ProbeResponse(jobs: jobs))
    }
}

private struct ProbeResponse: Encodable {
    let jobs: [HonbakoAutomationModels.Job]
}

private enum ProbeFailure: Error { case denied }
