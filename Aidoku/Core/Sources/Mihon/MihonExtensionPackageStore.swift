import CryptoKit
import Foundation

/// Persistent, reviewed package bytes only. This does not register sources,
/// execute code, convert APKs, or claim runtime/API compatibility. The app must
/// keep one store actor per directory; no other process may edit its files.
actor MihonExtensionPackageStore {
    enum Failure: Swift.Error, Equatable {
        case invalidCandidate, invalidSignerEvidence, invalidLimits
        case downloadRejected, packageTooLarge, digestMismatch
        case malformedArchive, unsafeArchive, archiveTooLarge, archiveChecksumMismatch
        case unsafeStorePath, corruptStore, missingPackage
        case unknownReview, staleReview, approvalRequired
    }

    struct Limits: Sendable {
        var maximumPackageBytes = 32 * 1_024 * 1_024
        var maximumExpandedBytes = 128 * 1_024 * 1_024
        var maximumEntryBytes = 32 * 1_024 * 1_024
        var maximumEntries = 8_192
        var maximumCompressionRatio = 200

        func validate() throws {
            guard maximumPackageBytes > 0, maximumPackageBytes <= 128 * 1_024 * 1_024,
                  maximumExpandedBytes > 0, maximumExpandedBytes <= 512 * 1_024 * 1_024,
                  maximumEntryBytes > 0, maximumEntryBytes <= maximumExpandedBytes,
                  maximumEntries > 0, maximumEntries <= 32_768,
                  maximumCompressionRatio > 0, maximumCompressionRatio <= 1_000 else { throw Failure.invalidLimits }
        }
    }

    enum ApprovalReason: String, Codable, Equatable, Sendable {
        case firstPackage, repositoryChanged, repositoryKeyClaimChanged
        case signerOrVerificationChanged, unverifiedReplacement, downgrade
        case sameVersionReplacement, artifactFormatChanged, versionMetadataChanged
    }

    enum Approval: Equatable, Sendable { case existingPin, userApproved }

    struct Record: Codable, Equatable, Sendable {
        let candidate: MihonPackageCandidate
        let signerEvidence: MihonPackageCandidate.SignerEvidence
        let approvedAt: Date
    }

    struct Review: Equatable, Sendable {
        let id: UUID
        let candidate: MihonPackageCandidate
        let signerEvidence: MihonPackageCandidate.SignerEvidence
        let previous: Record?
        let approvalReasons: [ApprovalReason]
        var requiresApproval: Bool { !approvalReasons.isEmpty }
    }

    struct StoredPackage: Sendable {
        let record: Record
        /// Integrity rechecked before this URL is returned. Authentication is
        /// described separately by record.signerEvidence, never by SHA-256.
        let artifactURL: URL
    }

    typealias Downloader = @Sendable (URL, URL, Int) async throws -> Void
    typealias SignatureInspector = @Sendable (URL, MihonPackageCandidate.Format) async throws -> MihonPackageCandidate.SignerEvidence

    private struct Manifest: Codable {
        var schemaVersion = 1
        var packages: [Record] = []
    }
    private struct Pending {
        let review: Review
        let fileURL: URL
    }

    private let directory: URL
    private let artifacts: URL
    private let staging: URL
    private let manifestURL: URL
    private let limits: Limits
    private let downloader: Downloader
    private let signatureInspector: SignatureInspector
    private var records: [String: Record]
    private var pending: [UUID: Pending] = [:]

    /// A custom inspector is a trusted app dependency, not repository data. It
    /// must authenticate the actual file's signature before returning verified,
    /// and throw on an invalid signature. The default authenticates nothing.
    init(directory: URL, limits: Limits = .init(),
         downloader: @escaping Downloader = { try await MihonPackageDownload.download($0, to: $1, maximumBytes: $2) },
         signatureInspector: @escaping SignatureInspector = { _, _ in .notVerified }) throws {
        try limits.validate()
        guard directory.isFileURL else { throw Failure.unsafeStorePath }
        let root = directory.standardizedFileURL
        try Self.ensureDirectory(root)
        let artifactDirectory = root.appending(path: "artifacts", directoryHint: .isDirectory)
        let stagingDirectory = root.appending(path: "staging", directoryHint: .isDirectory)
        try Self.ensureDirectory(artifactDirectory)
        try Self.ensureDirectory(stagingDirectory)
        let index = root.appending(path: "packages.json")
        let loaded = try Self.loadManifest(at: index)
        self.directory = root
        self.artifacts = artifactDirectory
        self.staging = stagingDirectory
        self.manifestURL = index
        self.limits = limits
        self.downloader = downloader
        self.signatureInspector = signatureInspector
        self.records = loaded
        // Only our own generated staging files are removed. Artifacts referenced
        // by the committed manifest remain untouched after interrupted updates.
        for file in try FileManager.default.contentsOfDirectory(at: stagingDirectory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
            try Self.requireRegularFile(file)
            try FileManager.default.removeItem(at: file)
        }
    }

    func packages() -> [Record] { records.values.sorted { $0.candidate.packageName < $1.candidate.packageName } }

    /// Downloads and verifies a candidate without changing the approved set.
    /// An existing package remains usable if download/validation is interrupted.
    func stage(_ candidate: MihonPackageCandidate) async throws -> Review {
        try candidate.validate()
        try Task.checkCancellation()
        try checkDirectories()
        let id = UUID()
        let file = staging.appending(path: id.uuidString + ".package")
        do {
            try await downloader(candidate.artifactURL, file, limits.maximumPackageBytes)
            try Task.checkCancellation()
            try checkDirectories()
            try verify(file, candidate: candidate)
            let evidence = try await signatureInspector(file, candidate.format)
            try evidence.validate()
            try Task.checkCancellation()
            // Recheck after the injected async inspector; it does not get to
            // change which bytes will be committed under the approved digest.
            try verify(file, candidate: candidate)
            let previous = records[candidate.packageName]
            let review = Review(id: id, candidate: candidate, signerEvidence: evidence, previous: previous,
                                approvalReasons: Self.reasons(candidate, evidence: evidence, previous: previous))
            pending[id] = Pending(review: review, fileURL: file)
            return review
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
    }

    /// `userApproved` may be supplied only after the human reviews this exact
    /// staged identity/evidence. It is never inferred from a parsed catalog.
    /// The default only permits updates already covered by a continuity pin.
    func commit(_ reviewID: UUID, approval: Approval = .existingPin) throws -> StoredPackage {
        guard let staged = pending[reviewID] else { throw Failure.unknownReview }
        let review = staged.review
        guard records[review.candidate.packageName] == review.previous else { throw Failure.staleReview }
        guard !review.requiresApproval || approval == .userApproved else { throw Failure.approvalRequired }
        try Task.checkCancellation()
        try checkDirectories()
        try verify(staged.fileURL, candidate: review.candidate)
        let target = artifactURL(for: review.candidate)
        var moved = false
        if FileManager.default.fileExists(atPath: target.path) {
            try verify(target, candidate: review.candidate)
        } else {
            try FileManager.default.moveItem(at: staged.fileURL, to: target)
            moved = true
        }
        let approvalDate = approval == .userApproved ? Date.now : (review.previous?.approvedAt ?? .now)
        let record = Record(candidate: review.candidate, signerEvidence: review.signerEvidence, approvedAt: approvalDate)
        var updated = records
        updated[review.candidate.packageName] = record
        do { try persist(updated) }
        catch {
            if moved { try? FileManager.default.removeItem(at: target) }
            throw error
        }
        records = updated
        pending.removeValue(forKey: reviewID)
        if !moved { try? FileManager.default.removeItem(at: staged.fileURL) }
        if let previous = review.previous {
            let oldURL = artifactURL(for: previous.candidate)
            if oldURL != target, !updated.values.contains(where: { artifactURL(for: $0.candidate) == oldURL }) {
                try? FileManager.default.removeItem(at: oldURL)
            }
        }
        return StoredPackage(record: record, artifactURL: target)
    }

    func discard(_ reviewID: UUID) throws {
        guard let staged = pending[reviewID] else { return }
        try FileManager.default.removeItem(at: staged.fileURL)
        pending.removeValue(forKey: reviewID)
    }

    func package(named packageName: String) throws -> StoredPackage {
        guard let record = records[packageName] else { throw Failure.missingPackage }
        try checkDirectories()
        let url = artifactURL(for: record.candidate)
        try verify(url, candidate: record.candidate)
        return StoredPackage(record: record, artifactURL: url)
    }

    func remove(packageName: String) throws {
        guard let old = records[packageName] else { return }
        try checkDirectories()
        var updated = records
        updated.removeValue(forKey: packageName)
        try persist(updated)
        records = updated
        let url = artifactURL(for: old.candidate)
        if !updated.values.contains(where: { artifactURL(for: $0.candidate) == url }) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func reasons(_ candidate: MihonPackageCandidate, evidence: MihonPackageCandidate.SignerEvidence,
                                previous: Record?) -> [ApprovalReason] {
        guard let previous else { return [.firstPackage] }
        let old = previous.candidate
        var result: [ApprovalReason] = []
        if candidate.repository.indexURL != old.repository.indexURL { result.append(.repositoryChanged) }
        if candidate.repository.signingKeyClaim != old.repository.signingKeyClaim { result.append(.repositoryKeyClaimChanged) }
        if evidence != previous.signerEvidence { result.append(.signerOrVerificationChanged) }
        if candidate.format != old.format { result.append(.artifactFormatChanged) }
        if candidate.versionCode < old.versionCode { result.append(.downgrade) }
        if candidate.versionCode == old.versionCode && candidate.versionName != old.versionName { result.append(.versionMetadataChanged) }
        if candidate.versionCode == old.versionCode && candidate.expectedSHA256 != old.expectedSHA256 { result.append(.sameVersionReplacement) }
        if evidence == .notVerified && candidate.expectedSHA256 != old.expectedSHA256 { result.append(.unverifiedReplacement) }
        return result
    }

    private func artifactURL(for candidate: MihonPackageCandidate) -> URL {
        artifacts.appending(path: candidate.expectedSHA256 + (candidate.format == .javaArchive ? ".jar" : ".apk"))
    }

    private func verify(_ url: URL, candidate: MihonPackageCandidate) throws {
        try Self.requireRegularFile(url)
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let count = values.fileSize, count > 0, count <= limits.maximumPackageBytes else { throw Failure.packageTooLarge }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var digest = SHA256()
        var read = 0
        while let chunk = try file.read(upToCount: 64 * 1_024), !chunk.isEmpty {
            try Task.checkCancellation()
            guard chunk.count <= limits.maximumPackageBytes - read else { throw Failure.packageTooLarge }
            read += chunk.count
            digest.update(data: chunk)
        }
        let hash = digest.finalize().map { String($0, radix: 16).leftPaddedHex }.joined()
        guard hash == candidate.expectedSHA256 else { throw Failure.digestMismatch }
        try MihonPackageArchiveValidator.validate(url, format: candidate.format, limits: limits)
    }

    private func checkDirectories() throws {
        try Self.ensureDirectory(directory)
        try Self.ensureDirectory(artifacts)
        try Self.ensureDirectory(staging)
        if FileManager.default.fileExists(atPath: manifestURL.path) { try Self.requireRegularFile(manifestURL) }
    }

    private func persist(_ updated: [String: Record]) throws {
        let manifest = Manifest(packages: updated.values.sorted { $0.candidate.packageName < $1.candidate.packageName })
        let data = try JSONEncoder().encode(manifest)
        guard data.count <= 8 * 1_024 * 1_024 else { throw Failure.corruptStore }
        try data.write(to: manifestURL, options: .atomic)
    }

    private static func loadManifest(at url: URL) throws -> [String: Record] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        try requireRegularFile(url)
        guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 8 * 1_024 * 1_024 else { throw Failure.corruptStore }
        let manifest: Manifest
        do { manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url)) }
        catch { throw Failure.corruptStore }
        guard manifest.schemaVersion == 1, manifest.packages.count <= 5_000 else { throw Failure.corruptStore }
        var records: [String: Record] = [:]
        for record in manifest.packages {
            try record.candidate.validate()
            try record.signerEvidence.validate()
            guard records[record.candidate.packageName] == nil, record.approvedAt.timeIntervalSinceReferenceDate.isFinite else { throw Failure.corruptStore }
            records[record.candidate.packageName] = record
        }
        return records
    }

    private static func ensureDirectory(_ url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw Failure.unsafeStorePath }
    }

    private static func requireRegularFile(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw Failure.unsafeStorePath }
    }
}

private extension String {
    var leftPaddedHex: String { count == 1 ? "0" + self : self }
}
