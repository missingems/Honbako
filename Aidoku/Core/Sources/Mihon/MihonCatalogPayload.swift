import Foundation
import zlib

enum MihonCatalogPayload {
    /// Current repositories can serve gzip files without an HTTP
    /// Content-Encoding header. Bound both compressed and expanded input.
    static func uncompressed(_ data: Data) throws -> Data {
        typealias Catalog = MihonRepositoryCatalog
        guard data.count <= Catalog.maximumPayloadBytes else { throw Catalog.ParseError.payloadTooLarge }
        guard data.starts(with: [0x1F, 0x8B]) else { return data }

        var stream = z_stream()
        guard inflateInit2_(&stream, MAX_WBITS + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw Catalog.ParseError.malformedGzip
        }
        defer { inflateEnd(&stream) }
        return try data.withUnsafeBytes { input in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(input.count)
            var result = Data()
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let status = buffer.withUnsafeMutableBytes { output -> Int32 in
                    stream.next_out = output.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(output.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                let written = buffer.count - Int(stream.avail_out)
                guard written <= Catalog.maximumPayloadBytes - result.count else { throw Catalog.ParseError.payloadTooLarge }
                result.append(contentsOf: buffer.prefix(written))
                if status == Z_STREAM_END {
                    // Reject trailing/concatenated members instead of silently
                    // parsing only an authenticated-looking first document.
                    guard stream.avail_in == 0 else { throw Catalog.ParseError.malformedGzip }
                    return result
                }
                guard status == Z_OK, written > 0 || stream.avail_in > 0 else { throw Catalog.ParseError.malformedGzip }
            }
        }
    }
}
