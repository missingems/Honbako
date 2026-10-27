@testable import Sumi
import Foundation
import Testing
import ZIPFoundation

struct HonbakoMihonPackageArchiveTests {
    private typealias Failure = MihonExtensionPackageStore.Failure

    @Test("JAR and APK containers retain distinct required code entries without claiming code compatibility")
    func typedContainers() throws {
        try withArchive([( "AndroidManifest.xml", .file, Data("original manifest".utf8)),
                         ("original/Example.class", .file, Data("synthetic, never executed".utf8))]) { url in
            try MihonPackageArchiveValidator.validate(url, format: .javaArchive, limits: .init())
            #expect(throws: Failure.malformedArchive) { try MihonPackageArchiveValidator.validate(url, format: .androidAPK, limits: .init()) }
        }
        try withArchive([("AndroidManifest.xml", .file, Data([1])), ("classes.dex", .file, Data([2]))]) { url in
            try MihonPackageArchiveValidator.validate(url, format: .androidAPK, limits: .init())
        }
    }

    @Test("Traversal, absolute paths, Windows-style paths and symbolic links are rejected without extraction")
    func unsafeNames() throws {
        for path in ["../escape.class", "/absolute.class", "nested/../escape.class", "C:/escape.class", "a\\escape.class", "a//b.class"] {
            try withArchive(regularEntries + [(path, .file, Data([3]))]) { url in
                #expect(throws: Failure.unsafeArchive) { try MihonPackageArchiveValidator.validate(url, format: .javaArchive, limits: .init()) }
            }
        }
        try withArchive(regularEntries + [("link.class", .symlink, Data("../../outside".utf8))]) { url in
            #expect(throws: Failure.unsafeArchive) { try MihonPackageArchiveValidator.validate(url, format: .javaArchive, limits: .init()) }
        }
    }

    @Test("Duplicate entries cannot make runtime lookup disagree with the reviewed archive")
    func duplicatePaths() throws {
        try withArchive(regularEntries + [("AndroidManifest.xml", .file, Data("second".utf8))]) { url in
            #expect(throws: Failure.unsafeArchive) { try MihonPackageArchiveValidator.validate(url, format: .javaArchive, limits: .init()) }
        }
    }

    @Test("Entry counts, expanded sizes and compression ratios are bounded before decompression")
    func archiveBombBounds() throws {
        try withArchive(regularEntries) { url in
            var limits = MihonExtensionPackageStore.Limits()
            limits.maximumEntries = 1
            #expect(throws: Failure.archiveTooLarge) { try MihonPackageArchiveValidator.validate(url, format: .javaArchive, limits: limits) }
            limits = .init()
            limits.maximumEntryBytes = 2
            #expect(throws: Failure.archiveTooLarge) { try MihonPackageArchiveValidator.validate(url, format: .javaArchive, limits: limits) }
        }
        try withArchive(regularEntries + [("original/Large.class", .file, Data(repeating: 0, count: 256 * 1_024))], compressed: true) { url in
            #expect(throws: Failure.archiveTooLarge) { try MihonPackageArchiveValidator.validate(url, format: .javaArchive, limits: .init()) }
        }
    }

    @Test("CRC corruption, encrypted entries and mismatched local names fail rather than being skipped")
    func malformedZIPs() throws {
        try withArchive(regularEntries) { url in
            let original = try Data(contentsOf: url)
            let central = try #require(find([0x50, 0x4B, 0x01, 0x02], in: original))
            var corrupted = original
            // File contents immediately follow the first local header/name.
            let nameBytes = Int(original[26]) | Int(original[27]) << 8
            let extraBytes = Int(original[28]) | Int(original[29]) << 8
            corrupted[30 + nameBytes + extraBytes] ^= 0x7F
            try corrupted.write(to: url)
            #expect(throws: Failure.archiveChecksumMismatch) { try MihonPackageArchiveValidator.validate(url, format: .javaArchive, limits: .init()) }
            var encrypted = original
            encrypted[central + 8] |= 1
            try encrypted.write(to: url)
            #expect(throws: Failure.malformedArchive) { try MihonPackageArchiveValidator.validate(url, format: .javaArchive, limits: .init()) }
            var renamed = original
            renamed[30] ^= 1
            try renamed.write(to: url)
            #expect(throws: Failure.malformedArchive) { try MihonPackageArchiveValidator.validate(url, format: .javaArchive, limits: .init()) }
            var missingCentral = original
            missingCentral[central] = 0
            try missingCentral.write(to: url)
            #expect(throws: Failure.malformedArchive) { try MihonPackageArchiveValidator.validate(url, format: .javaArchive, limits: .init()) }
        }
    }

    @Test("Trailing payloads and truncated containers cannot be accepted as a partial archive")
    func trailingAndTruncatedData() throws {
        try withArchive(regularEntries) { url in
            let original = try Data(contentsOf: url)
            for malformed in [original + Data([0]), Data(original.dropLast(7)), Data([0x50, 0x4B])] {
                try malformed.write(to: url)
                #expect(throws: Failure.malformedArchive) { try MihonPackageArchiveValidator.validate(url, format: .javaArchive, limits: .init()) }
            }
        }
    }

    private var regularEntries: [(String, Entry.EntryType, Data)] {
        [("AndroidManifest.xml", .file, Data("original manifest".utf8)), ("original/Page.class", .file, Data("original synthetic class".utf8))]
    }

    private func withArchive(_ entries: [(String, Entry.EntryType, Data)], compressed: Bool = false,
                             operation: (URL) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "honbako-archive-tests-" + UUID().uuidString + ".zip")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let archive = try Archive(url: url, accessMode: .create)
            for (path, type, data) in entries {
                try archive.addEntry(with: path, type: type, uncompressedSize: Int64(data.count),
                                     compressionMethod: compressed ? .deflate : .none, provider: { position, size in
                    data.subdata(in: Int(position)..<(Int(position) + size))
                })
            }
        }
        try operation(url)
    }

    private func find(_ bytes: [UInt8], in data: Data) -> Int? {
        guard data.count >= bytes.count else { return nil }
        return (0...(data.count - bytes.count)).first { Array(data[$0..<($0 + bytes.count)]) == bytes }
    }
}
