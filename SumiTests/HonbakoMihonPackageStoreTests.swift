@testable import Sumi
import CryptoKit
import Foundation
import Testing
import ZIPFoundation

struct HonbakoMihonPackageStoreTests {
    private typealias Store = MihonExtensionPackageStore

    @Test("Staged bytes require explicit first approval, persist, and retain an honest unverified signer state")
    func reviewedPersistence() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let data = try archiveData()
        let candidate = try candidate(data)
        let store = try makeStore(root, data: data)
        let review = try await store.stage(candidate)
        #expect(review.approvalReasons == [.firstPackage])
        #expect(review.signerEvidence == .notVerified)
        #expect(await store.packages().isEmpty)
        await expect(.approvalRequired) { _ = try await store.commit(review.id) }
        let saved = try await store.commit(review.id, approval: .userApproved)
        #expect(try Data(contentsOf: saved.artifactURL) == data)
        #expect(saved.artifactURL.lastPathComponent == candidate.expectedSHA256 + ".jar")
        let reopened = try Store(directory: root)
        let restored = try await reopened.package(named: candidate.packageName)
        #expect(restored.record == saved.record)
        #expect(restored.record.candidate.repository.signingKeyClaim == "unverified-repository-claim")
        #expect(restored.record.signerEvidence == .notVerified, "SHA-256 matching must not authenticate a signer")
    }

    @Test("Failed digest, oversized and interrupted downloads leave the approved package unchanged and clear staging")
    func failedDownloadsAreTransactional() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try archiveData()
        let originalCandidate = try candidate(original)
        let store = try makeStore(root, data: original)
        let initial = try await store.stage(originalCandidate)
        let saved = try await store.commit(initial.id, approval: .userApproved)
        let other = try archiveData(code: Data("different original code".utf8))
        let mismatch = try candidate(other, version: 2)
        await expect(.digestMismatch) { _ = try await store.stage(mismatch) }
        #expect(try Data(contentsOf: saved.artifactURL) == original)
        #expect(try await store.package(named: originalCandidate.packageName).record == saved.record)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "staging").path).isEmpty)

        var limits = Store.Limits()
        limits.maximumPackageBytes = original.count - 1
        let oversized = try makeStore(root, data: original, limits: limits)
        await expect(.packageTooLarge) { _ = try await oversized.stage(originalCandidate) }
        let interrupted = try Store(directory: root, downloader: { _, destination, _ in
            try Data("partial".utf8).write(to: destination)
            throw CancellationError()
        })
        do { _ = try await interrupted.stage(mismatch); Issue.record("Interrupted staging must fail") }
        catch { #expect(error is CancellationError) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "staging").path).isEmpty)
        #expect(try await interrupted.package(named: originalCandidate.packageName).record == saved.record)
    }

    @Test("An unsigned replacement cannot inherit approval even from an unchanged repository key claim")
    func unverifiedUpdatesNeedApproval() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let one = try archiveData()
        let store = try makeStore(root, data: one)
        let first = try await store.stage(candidate(one))
        _ = try await store.commit(first.id, approval: .userApproved)
        let two = try archiveData(code: Data("second original payload".utf8))
        let updater = try makeStore(root, data: two)
        let review = try await updater.stage(candidate(two, version: 2))
        #expect(review.approvalReasons == [.unverifiedReplacement])
        await expect(.approvalRequired) { _ = try await updater.commit(review.id) }
        _ = try await updater.commit(review.id, approval: .userApproved)
        let identical = try await updater.stage(candidate(two, version: 2))
        #expect(!identical.requiresApproval)
        _ = try await updater.commit(identical.id)
    }

    @Test("Repository, key, signer, authentication level and downgrade changes are explicit review reasons")
    func continuityPinsRequireReview() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let data = try archiveData()
        // This fake cryptographic inspector tests policy only; no real package
        // signature or test fixture is represented as cryptographically valid.
        let evidence = EvidenceSlot(.verified(certificateSHA256: [String(repeating: "a", count: 64)]))
        let store = try Store(directory: root, downloader: loader(data), signatureInspector: { _, _ in await evidence.value })
        let first = try await store.stage(candidate(data, version: 2))
        _ = try await store.commit(first.id, approval: .userApproved)
        let continuous = try await store.stage(candidate(data, version: 3))
        #expect(!continuous.requiresApproval)
        try await store.discard(continuous.id)
        let repository = try await store.stage(candidate(data, version: 3, index: "https://another.example.invalid/index.pb", key: "new-claim"))
        #expect(repository.approvalReasons.contains(.repositoryChanged))
        #expect(repository.approvalReasons.contains(.repositoryKeyClaimChanged))
        await expect(.approvalRequired) { _ = try await store.commit(repository.id) }
        try await store.discard(repository.id)
        await evidence.set(.verified(certificateSHA256: [String(repeating: "b", count: 64)]))
        let signer = try await store.stage(candidate(data, version: 3))
        #expect(signer.approvalReasons.contains(.signerOrVerificationChanged))
        try await store.discard(signer.id)
        await evidence.set(.notVerified)
        let downgrade = try await store.stage(candidate(data, version: 1))
        #expect(downgrade.approvalReasons.contains(.signerOrVerificationChanged))
        #expect(downgrade.approvalReasons.contains(.downgrade))
        await expect(.approvalRequired) { _ = try await store.commit(downgrade.id) }
    }

    @Test("Stale review tokens cannot overwrite a package approved after they were staged")
    func staleReviews() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let data = try archiveData()
        let store = try makeStore(root, data: data)
        let one = try await store.stage(candidate(data))
        let two = try await store.stage(candidate(data, version: 2))
        _ = try await store.commit(one.id, approval: .userApproved)
        await expect(.staleReview) { _ = try await store.commit(two.id, approval: .userApproved) }
        #expect(try await store.package(named: one.candidate.packageName).record.candidate.versionCode == 1)
    }

    @Test("Stored bytes and async inspector output are rechecked before use or commit")
    func detectsTampering() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let data = try archiveData()
        let store = try makeStore(root, data: data)
        let review = try await store.stage(candidate(data))
        let saved = try await store.commit(review.id, approval: .userApproved)
        try Data("modified".utf8).write(to: saved.artifactURL)
        await expect(.digestMismatch) { _ = try await store.package(named: review.candidate.packageName) }

        let inspectorRoot = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: inspectorRoot) }
        let mutating = try Store(directory: inspectorRoot, downloader: loader(data), signatureInspector: { url, _ in
            try Data("modified by a broken inspector".utf8).write(to: url)
            return .notVerified
        })
        await expect(.digestMismatch) { _ = try await mutating.stage(candidate(data)) }
        #expect(await mutating.packages().isEmpty)
    }

    @Test("Removal persists before deleting unreferenced package bytes")
    func removal() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let data = try archiveData()
        let store = try makeStore(root, data: data)
        let review = try await store.stage(candidate(data))
        let saved = try await store.commit(review.id, approval: .userApproved)
        try await store.remove(packageName: review.candidate.packageName)
        #expect(!FileManager.default.fileExists(atPath: saved.artifactURL.path))
        let reopened = try Store(directory: root)
        #expect(await reopened.packages().isEmpty)
    }

    @Test("Package selection enforces typed catalog membership, lowercase SHA-256 and secure artifact URLs")
    func candidateValidation() throws {
        let data = try archiveData()
        #expect(throws: Store.Failure.invalidCandidate) { _ = try candidate(data, digest: String(repeating: "A", count: 64)) }
        #expect(throws: Store.Failure.invalidCandidate) { _ = try candidate(data, artifact: "http://remote.example.invalid/a.jar") }
        #expect(!MihonPackageDownload.permits(URL(string: "https://user:password@example.invalid/a.jar")!))
        #expect(!MihonPackageDownload.permits(URL(string: "file:///private/a.jar")!))
        #expect(!MihonPackageDownload.permits(URL(string: "https://example.invalid/a.jar#fragment")!))
    }

    private actor EvidenceSlot {
        var value: MihonPackageCandidate.SignerEvidence
        init(_ value: MihonPackageCandidate.SignerEvidence) { self.value = value }
        func set(_ value: MihonPackageCandidate.SignerEvidence) { self.value = value }
    }

    private func makeStore(_ root: URL, data: Data, limits: Store.Limits = .init()) throws -> Store {
        try Store(directory: root, limits: limits, downloader: loader(data))
    }
    private func loader(_ data: Data) -> Store.Downloader { { _, destination, _ in try data.write(to: destination) } }
    private func expect(_ expected: Store.Failure, operation: () async throws -> Void) async {
        do { try await operation(); Issue.record("Expected \(expected)") }
        catch { #expect(error as? Store.Failure == expected) }
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "honbako-package-tests-" + UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func archiveData(code: Data = Data("original synthetic class bytes; never executed".utf8)) throws -> Data {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "original.jar")
        do {
            let archive = try Archive(url: url, accessMode: .create)
            for (path, data) in [("AndroidManifest.xml", Data("<manifest package=\"example.extension\"/>".utf8)), ("original/Page.class", code)] {
                try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), provider: { position, size in
                    data.subdata(in: Int(position)..<(Int(position) + size))
                })
            }
        }
        return try Data(contentsOf: url)
    }

    private func candidate(_ data: Data, version: Int64 = 1, index: String = "https://catalog.example.invalid/index.pb",
                           key: String = "unverified-repository-claim", digest: String? = nil,
                           artifact: String? = nil) throws -> MihonPackageCandidate {
        let artifact = MihonRepositoryCatalog.Artifact(format: .javaArchive,
            url: URL(string: artifact ?? "https://packages.example.invalid/\(version).jar")!)
        let package = MihonRepositoryCatalog.Package(name: "Original", packageName: "example.extension", extensionLib: "1.6",
            versionCode: version, versionName: "1.6.\(version)", language: "en", contentWarning: 1, iconURL: nil,
            artifacts: [artifact], sources: [])
        let catalog = MihonRepositoryCatalog(indexURL: URL(string: index)!, format: .json,
            metadata: .init(name: "Example", badgeLabel: "", signingKey: key, contact: .init(website: nil, discord: nil)),
            packages: [package], extensionListURL: nil)
        let sha = SHA256.hash(data: data).map { let value = String($0, radix: 16); return value.count == 1 ? "0" + value : value }.joined()
        return try .init(catalog: catalog, package: package, artifact: artifact, expectedSHA256: digest ?? sha)
    }
}
