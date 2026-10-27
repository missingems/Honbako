import Foundation
import ZIPFoundation

/// Validates without extracting files. The bounded central-directory pass also
/// detects entries ZIPFoundation's iterator would otherwise silently skip.
enum MihonPackageArchiveValidator {
    private struct Header {
        let name: Data
        let flags: UInt16
        let compression: UInt16
        let checksum: UInt32
        let compressed: Int
        let expanded: Int
        let localOffset: Int
    }

    static func validate(_ url: URL, format: MihonPackageCandidate.Format,
                         limits: MihonExtensionPackageStore.Limits) throws {
        typealias Failure = MihonExtensionPackageStore.Failure
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= limits.maximumPackageBytes else { throw Failure.packageTooLarge }
        let headers = try directory(in: data, limits: limits)
        let archive: Archive
        do { archive = try Archive(url: url, accessMode: .read) }
        catch { throw Failure.malformedArchive }
        var paths: Set<String> = []
        var count = 0
        var expanded = 0
        var hasManifest = false
        var hasCode = false
        for entry in archive {
            try Task.checkCancellation()
            guard count < headers.count else { throw Failure.malformedArchive }
            let header = headers[count]
            count += 1
            let path = entry.path
            guard safePath(path), entry.type != .symlink,
                  paths.insert(path.precomposedStringWithCanonicalMapping).inserted,
                  entry.compressedSize == UInt64(header.compressed), entry.uncompressedSize == UInt64(header.expanded) else {
                throw Failure.unsafeArchive
            }
            if entry.type == .directory {
                guard header.expanded == 0, header.checksum == 0 else { throw Failure.unsafeArchive }
                continue
            }
            hasManifest = hasManifest || path == "AndroidManifest.xml"
            hasCode = hasCode || (format == .javaArchive ? path.hasSuffix(".class") : path == "classes.dex")
            var entryBytes = 0
            let checksum: CRC32
            do {
                checksum = try archive.extract(entry, bufferSize: 64 * 1_024, skipCRC32: false) { chunk in
                    try Task.checkCancellation()
                    guard chunk.count <= limits.maximumEntryBytes - entryBytes,
                          chunk.count <= limits.maximumExpandedBytes - expanded else { throw Failure.archiveTooLarge }
                    entryBytes += chunk.count
                    expanded += chunk.count
                }
            } catch let failure as Failure { throw failure }
            catch is CancellationError { throw CancellationError() }
            catch { throw Failure.malformedArchive }
            guard entryBytes == header.expanded else { throw Failure.malformedArchive }
            guard checksum == header.checksum else { throw Failure.archiveChecksumMismatch }
        }
        guard count == headers.count, hasManifest, hasCode else { throw Failure.malformedArchive }
    }

    private static func safePath(_ path: String) -> Bool {
        guard !path.isEmpty, path.utf8.count <= 2_048, !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"),
              !path.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return parts.enumerated().allSatisfy { index, part in
            part != "." && part != ".." && (!part.isEmpty || index == parts.count - 1)
        }
    }

    /// APK signing blocks may occur before the central directory. ZIP64 and
    /// split archives are unnecessary under these limits and are rejected.
    private static func directory(in data: Data, limits: MihonExtensionPackageStore.Limits) throws -> [Header] {
        typealias Failure = MihonExtensionPackageStore.Failure
        guard data.count >= 22 else { throw Failure.malformedArchive }
        let lower = max(0, data.count - 22 - 65_535)
        var end: Int?
        for offset in stride(from: data.count - 22, through: lower, by: -1) {
            if u32(data, offset) == 0x06054B50,
               offset + 22 + Int(u16(data, offset + 20)) == data.count { end = offset; break }
        }
        guard let end, u16(data, end + 4) == 0, u16(data, end + 6) == 0,
              u16(data, end + 8) == u16(data, end + 10) else { throw Failure.malformedArchive }
        let count = Int(u16(data, end + 10))
        let centralBytes = Int(u32(data, end + 12))
        let centralStart = Int(u32(data, end + 16))
        guard count > 0, count <= limits.maximumEntries, count < Int(UInt16.max),
              centralStart <= end, centralBytes == end - centralStart else { throw Failure.archiveTooLarge }
        var offset = centralStart
        var total = 0
        var headers: [Header] = []
        var ranges: [Range<Int>] = []
        for _ in 0..<count {
            try Task.checkCancellation()
            guard offset <= end - 46, u32(data, offset) == 0x02014B50 else { throw Failure.malformedArchive }
            let flags = u16(data, offset + 8)
            let compression = u16(data, offset + 10)
            let compressed = Int(u32(data, offset + 20))
            let expanded = Int(u32(data, offset + 24))
            let nameLength = Int(u16(data, offset + 28))
            let extraLength = Int(u16(data, offset + 30))
            let commentLength = Int(u16(data, offset + 32))
            let local = Int(u32(data, offset + 42))
            guard flags & 1 == 0, compression == 0 || compression == 8,
                  u16(data, offset + 34) == 0, nameLength > 0, nameLength <= 2_048,
                  nameLength + extraLength + commentLength <= end - offset - 46 else { throw Failure.malformedArchive }
            guard compression != 0 || compressed == expanded else { throw Failure.malformedArchive }
            guard expanded <= limits.maximumEntryBytes, expanded <= limits.maximumExpandedBytes - total,
                  compressed <= limits.maximumPackageBytes,
                  expanded <= max(1, compressed) * limits.maximumCompressionRatio else { throw Failure.archiveTooLarge }
            total += expanded
            let name = data.subdata(in: (offset + 46)..<(offset + 46 + nameLength))
            let header = Header(name: name, flags: flags, compression: compression, checksum: u32(data, offset + 16),
                                compressed: compressed, expanded: expanded, localOffset: local)
            let localEnd = try validateLocal(header, data: data, centralStart: centralStart)
            ranges.append(local..<localEnd)
            headers.append(header)
            offset += 46 + nameLength + extraLength + commentLength
        }
        guard offset == end else { throw Failure.malformedArchive }
        var previousEnd = 0
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            guard range.lowerBound >= previousEnd else { throw Failure.malformedArchive }
            previousEnd = range.upperBound
        }
        return headers
    }

    private static func validateLocal(_ header: Header, data: Data, centralStart: Int) throws -> Int {
        typealias Failure = MihonExtensionPackageStore.Failure
        let start = header.localOffset
        guard start >= 0, start <= centralStart - 30, u32(data, start) == 0x04034B50,
              u16(data, start + 6) == header.flags, u16(data, start + 8) == header.compression else { throw Failure.malformedArchive }
        let nameLength = Int(u16(data, start + 26))
        let extraLength = Int(u16(data, start + 28))
        guard nameLength == header.name.count, nameLength + extraLength <= centralStart - start - 30 else { throw Failure.malformedArchive }
        let nameStart = start + 30
        guard data.subdata(in: nameStart..<(nameStart + nameLength)) == header.name else { throw Failure.malformedArchive }
        let contentStart = nameStart + nameLength + extraLength
        guard header.compressed <= centralStart - contentStart else { throw Failure.malformedArchive }
        let contentEnd = contentStart + header.compressed
        if header.flags & 8 == 0 {
            guard u32(data, start + 14) == header.checksum, Int(u32(data, start + 18)) == header.compressed,
                  Int(u32(data, start + 22)) == header.expanded else { throw Failure.malformedArchive }
            return contentEnd
        }
        // The optional descriptor signature is not part of the CRC value.
        for signatureBytes in [4, 0] {
            let descriptor = contentEnd + signatureBytes
            if signatureBytes == 4 && (contentEnd > centralStart - 4 || u32(data, contentEnd) != 0x08074B50) { continue }
            guard descriptor <= centralStart - 12 else { continue }
            if u32(data, descriptor) == header.checksum,
               Int(u32(data, descriptor + 4)) == header.compressed,
               Int(u32(data, descriptor + 8)) == header.expanded { return descriptor + 12 }
        }
        throw Failure.malformedArchive
    }

    private static func u16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(u16(data, offset)) | UInt32(u16(data, offset + 2)) << 16
    }
}
