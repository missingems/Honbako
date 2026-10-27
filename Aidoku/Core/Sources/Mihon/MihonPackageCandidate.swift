import Foundation

/// A catalog selection, not an installed or authenticated extension. Catalogs
/// do not contain a SHA-256 in every format; callers must obtain an expected
/// digest separately and must never treat that digest as signer authentication.
struct MihonPackageCandidate: Codable, Equatable, Sendable {
    enum Format: String, Codable, Sendable { case androidAPK, javaArchive }

    struct Repository: Codable, Equatable, Sendable {
        let indexURL: URL
        /// Preserved only for continuity review. The repository supplied this
        /// claim; this store does not authenticate it.
        let signingKeyClaim: String?
    }

    /// Only a trusted, injected cryptographic validator may return `verified`.
    /// The default store inspector returns `notVerified`, including for signed
    /// looking APK/JAR files. No catalog field can construct this evidence.
    enum SignerEvidence: Codable, Equatable, Sendable {
        case notVerified
        case verified(certificateSHA256: [String])

        func validate() throws {
            if case let .verified(fingerprints) = self {
                guard !fingerprints.isEmpty, fingerprints.count <= 16,
                      fingerprints == fingerprints.sorted(), Set(fingerprints).count == fingerprints.count,
                      fingerprints.allSatisfy(MihonPackageCandidate.isSHA256) else {
                    throw MihonExtensionPackageStore.Failure.invalidSignerEvidence
                }
            }
        }
    }

    let repository: Repository
    let packageName: String
    let versionCode: Int64
    let versionName: String
    let extensionLibrary: String
    let format: Format
    let artifactURL: URL
    let expectedSHA256: String

    init(catalog: MihonRepositoryCatalog, package: MihonRepositoryCatalog.Package,
         artifact: MihonRepositoryCatalog.Artifact, expectedSHA256: String) throws {
        try MihonRepositoryCatalog.validate([package])
        guard package.artifacts.contains(artifact),
              catalog.packages.contains(package) || catalog.extensionListURL != nil else {
            throw MihonExtensionPackageStore.Failure.invalidCandidate
        }
        repository = .init(indexURL: catalog.indexURL, signingKeyClaim: catalog.metadata?.signingKey)
        packageName = package.packageName
        versionCode = package.versionCode
        versionName = package.versionName
        extensionLibrary = package.extensionLib
        format = artifact.format == .javaArchive ? .javaArchive : .androidAPK
        artifactURL = artifact.url
        self.expectedSHA256 = expectedSHA256
        try validate()
    }

    func validate() throws {
        try MihonRepositoryCatalog.validateIndexURL(repository.indexURL)
        guard MihonPackageDownload.permits(artifactURL), Self.isSHA256(expectedSHA256),
              packageName.utf8.count <= 512, packageName.split(separator: ".").count >= 2,
              packageName.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ component in
                  guard let first = component.utf8.first, Self.isLetter(first) || first == 95 else { return false }
                  return component.utf8.allSatisfy { Self.isLetter($0) || (48...57).contains($0) || $0 == 95 }
              }), versionCode > 0, !versionName.isEmpty, versionName.utf8.count <= 256,
              extensionLibrary.split(separator: ".", omittingEmptySubsequences: false).count == 2,
              extensionLibrary.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({
                  !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) }
              }), (repository.signingKeyClaim?.utf8.count ?? 0) <= 16_384 else {
            throw MihonExtensionPackageStore.Failure.invalidCandidate
        }
    }

    static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private static func isLetter(_ byte: UInt8) -> Bool { (65...90).contains(byte) || (97...122).contains(byte) }
}
