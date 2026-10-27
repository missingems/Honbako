@testable import Sumi
import Foundation
import Testing
import zlib

struct HonbakoMihonCatalogTests {
    private let indexURL = URL(string: "https://catalog.example.invalid/repo/index.pb")!

    @Test("Legacy repository metadata preserves exact quoted and numeric signed int64 source identities")
    func legacyIDsAndResources() throws {
        let data = legacyJSON(sources: """
          {"id":"9007199254740993","name":"Server English","lang":"en","baseUrl":"https://books.example.invalid","versionId":2},
          {"id":9223372036854775807,"name":"Server Japanese","lang":"ja","baseUrl":""},
          {"id":-9223372036854775808,"name":"Server Chinese","lang":"zh-Hant","baseUrl":""}
          """)
        let catalog = try MihonRepositoryCatalog.parse(data, indexURL: indexURL)
        let package = try #require(catalog.packages.first)
        #expect(catalog.format == .legacyJSON)
        #expect(catalog.metadata == nil)
        #expect(package.sources.map(\.id) == ["9007199254740993", "9223372036854775807", "-9223372036854775808"])
        #expect(package.sources.map(\.language) == ["en", "ja", "zh-Hant"])
        #expect(package.sources.first?.versionID == 2)
        #expect(package.extensionLib == "1.4")
        #expect(package.versionCode == 50)
        #expect(package.artifacts == [.init(format: .androidAPK,
            url: URL(string: "https://catalog.example.invalid/repo/apk/tachiyomi-all.example-v1.4.50.apk")!)])
        #expect(package.iconURL?.absoluteString == "https://catalog.example.invalid/repo/icon/eu.kanade.tachiyomi.extension.all.example.png")
    }

    @Test("A legacy catalog without enumerated sources never invents a working source ID")
    func absentSourcesAreNotFabricated() throws {
        let data = Data("""
          [{"name":"Example","pkg":"example.extension","apk":"example.apk","lang":"all","code":1,"version":"1.4.1","sources":null}]
          """.utf8)
        #expect(try MihonRepositoryCatalog.parse(data, indexURL: indexURL).packages.first?.sources.isEmpty == true)
    }

    @Test("Plain HTTP provider home URLs remain metadata while insecure artifact URLs are rejected")
    func metadataAndArtifactPoliciesDiffer() throws {
        let data = legacyJSON(sources: "{\"id\":1,\"name\":\"Example\",\"lang\":\"en\",\"baseUrl\":\"http://books.example.invalid/#about\"}")
        let catalog = try MihonRepositoryCatalog.parse(data, indexURL: indexURL)
        #expect(catalog.packages.first?.sources.first?.homeURL?.absoluteString == "http://books.example.invalid/#about")
        #expect(catalog.packages.first?.artifacts.first?.url.scheme == "https")
    }

    @Test("Modern JSON preserves store signing claims and distinct APK/JAR resources without claiming execution support")
    func modernJSONResources() throws {
        let data = modernJSON(package: packageJSON)
        let catalog = try MihonRepositoryCatalog.parse(data, indexURL: indexURL)
        let package = try #require(catalog.packages.first)
        #expect(catalog.format == .json)
        #expect(catalog.metadata?.name == "Example Store")
        #expect(catalog.metadata?.signingKey == "unverified-test-key")
        #expect(package.extensionLib == "1.6")
        #expect(package.contentWarning == 2)
        #expect(package.language == "all")
        #expect(package.sources.map(\.id) == ["9007199254740993", "42"])
        #expect(package.artifacts.map(\.format) == [.androidAPK, .javaArchive])
        #expect(package.artifacts[1].url.absoluteString == "https://catalog.example.invalid/repo/jar/example.jar")
        #expect(package.iconURL?.absoluteString == "https://images.example.invalid/example.png")
        #expect(package.sources.first?.mirrorURLs.first?.absoluteString == "https://mirror.example.invalid")
    }

    @Test("Protobuf JSON emitter defaults and quoted int64 version codes decode faithfully")
    func protobufJSONDefaults() throws {
        // Official publish-repo.py calls MessageToJson with
        // always_print_fields_with_no_presence=False. Empty scalar/message and
        // repeated defaults disappear; int64 values are emitted as strings.
        let data = Data("""
          {"name":"Example Store","extensionList":{"extensions":[{"name":"Example","packageName":"example.extension","resources":{"apkUrl":"apk/example.apk"},"extensionLib":"1.6","versionCode":"9223372036854775807","versionName":"1.6.7"}]}}
          """.utf8)
        let catalog = try MihonRepositoryCatalog.parse(data, indexURL: indexURL)
        let package = try #require(catalog.packages.first)
        #expect(catalog.metadata?.badgeLabel == "")
        #expect(catalog.metadata?.signingKey == "")
        #expect(catalog.metadata?.contact.website == nil)
        #expect(package.versionCode == Int64.max)
        #expect(package.contentWarning == 0)
        #expect(package.sources.isEmpty)
        #expect(package.iconURL == nil)
        #expect(package.artifacts.count == 1)

        let empty = Data("{\"name\":\"Empty Store\",\"extensionList\":{}}".utf8)
        #expect(try MihonRepositoryCatalog.parse(empty, indexURL: indexURL).packages.isEmpty)
        #expect(try MihonRepositoryCatalog.parseExtensionList(Data("{}".utf8), listURL: indexURL).isEmpty)
    }

    @Test("Proto3 defaults do not make incomplete package identities and executable resources valid")
    func defaultsStillRequireMeaningfulPackages() throws {
        let invalid = [
            "{\"extensionList\":{}}",
            "{\"name\":\"Example\",\"extensionList\":{\"extensions\":[{}]}}",
            "{\"name\":\"Example\",\"extensionList\":{\"extensions\":[{\"name\":\"Example\",\"packageName\":\"example.extension\",\"resources\":{\"apkUrl\":\"x.apk\"},\"extensionLib\":\"1.6\",\"versionName\":\"1.6.1\"}]}}"
        ]
        for text in invalid {
            #expect(throws: (any Error).self) { try MihonRepositoryCatalog.parse(Data(text.utf8), indexURL: indexURL) }
        }
    }

    @Test("Modern protobuf uses real schema field numbers and skips unknown fields while retaining exact IDs")
    func protobufCatalog() throws {
        let bytes = protobufIndex()
        let catalog = try MihonRepositoryCatalog.parse(bytes, indexURL: indexURL)
        let package = try #require(catalog.packages.first)
        #expect(catalog.format == .protobuf)
        #expect(catalog.metadata?.name == "Example Store")
        #expect(catalog.metadata?.contact.website?.absoluteString == "https://example.invalid")
        #expect(package.packageName == "example.extension")
        #expect(package.versionCode == 7 && package.versionName == "1.6.7")
        #expect(package.sources.first?.id == "9223372036854775807")
        #expect(package.sources.first?.language == "pt-BR")
        #expect(package.sources.first?.message == "Test-only fixture")
        #expect(package.artifacts.map(\.format) == [.androidAPK, .javaArchive])
        #expect(package.artifacts.last?.url.absoluteString == "https://catalog.example.invalid/repo/jar/example.jar")
        #expect(package.contentWarning == 99, "Unknown future warnings must not become Safe")
    }

    @Test("A valid protobuf name beginning with a JSON delimiter is still decoded as protobuf")
    func binaryJSONPrefixAmbiguity() throws {
        // name has nine bytes: field tag 0x0A and length 0x09 both look like
        // leading JSON whitespace before the '[' character.
        let bytes = protobufIndex(name: "[Example]")
        #expect(try MihonRepositoryCatalog.parse(bytes, indexURL: indexURL).metadata?.name == "[Example]")
    }

    @Test("Separate list URLs are explicit follow-up resources and use their own base for relative artifacts")
    func separateExtensionLists() throws {
        let bytes = field(1, "Example Store") + field(102, "lists/current.pb")
        let catalog = try MihonRepositoryCatalog.parse(bytes, indexURL: indexURL)
        let listURL = try #require(catalog.extensionListURL)
        #expect(catalog.packages.isEmpty)
        #expect(listURL.absoluteString == "https://catalog.example.invalid/repo/lists/current.pb")
        let packages = try MihonRepositoryCatalog.parseExtensionList(field(1, protobufPackage()), listURL: listURL)
        #expect(packages.first?.artifacts.first?.url.absoluteString == "https://catalog.example.invalid/repo/lists/apk/example.apk")

        let jsonIndex = Data("""
          {"name":"Example Store","badgeLabel":"EX","signingKey":"unverified","contact":{},"extensionListUrl":"lists/current.json"}
          """.utf8)
        #expect(try MihonRepositoryCatalog.parse(jsonIndex, indexURL: indexURL).extensionListURL?.lastPathComponent == "current.json")
        let listJSON = Data("{\"extensions\":[\(packageJSON)]}".utf8)
        #expect(try MihonRepositoryCatalog.parseExtensionList(listJSON, listURL: listURL).first?.artifacts.first?.url.absoluteString
            == "https://catalog.example.invalid/repo/lists/apk/example.apk")
    }

    @Test("Gzip indexes decode with CRC validation and a bounded expanded size")
    func gzipCatalogAndBounds() throws {
        let bytes = protobufIndex()
        let catalog = try MihonRepositoryCatalog.parse(gzip(bytes), indexURL: indexURL)
        #expect(catalog == (try MihonRepositoryCatalog.parse(bytes, indexURL: indexURL)))
        var badCRC = try gzip(bytes)
        badCRC[badCRC.count - 8] ^= 0xFF
        #expect(throws: MihonRepositoryCatalog.ParseError.malformedGzip) {
            try MihonRepositoryCatalog.parse(badCRC, indexURL: indexURL)
        }
        let bomb = try gzip(Data(repeating: 0x20, count: MihonRepositoryCatalog.maximumPayloadBytes + 1))
        #expect(throws: MihonRepositoryCatalog.ParseError.payloadTooLarge) {
            try MihonRepositoryCatalog.parse(bomb, indexURL: indexURL)
        }
    }

    @Test("Malformed protobuf lengths, varints and truncated payloads fail without partial catalogs")
    func malformedBinary() throws {
        for bytes in [Data([0x0A, 0x7F]), Data([0x00]), Data([0x08] + Array(repeating: 0xFF, count: 11)),
                      Data([0x0A, 0x01, 0xFF]), Data(protobufIndex().dropLast())] {
            #expect(throws: (any Error).self) { try MihonRepositoryCatalog.parse(bytes, indexURL: indexURL) }
        }
    }

    @Test("Unsafe artifact/index URLs, ambiguous lists, duplicate identities and out-of-range IDs are rejected")
    func invalidCatalogs() throws {
        let invalidJSON = [
            modernJSON(package: packageJSON.replacingOccurrences(of: "apk/example.apk", with: "file:///private/secret.apk")),
            modernJSON(package: packageJSON.replacingOccurrences(of: "apk/example.apk", with: "https://user:password@example.invalid/a.apk")),
            modernJSON(package: packageJSON.replacingOccurrences(of: "apk/example.apk", with: "http://example.invalid/a.apk")),
            modernJSON(package: packageJSON.replacingOccurrences(of: "9007199254740993", with: "9223372036854775808")),
            legacyJSON(sources: "{\"id\":1,\"name\":\"A\",\"lang\":\"en\"},{\"id\":1,\"name\":\"B\",\"lang\":\"ja\"}"),
            legacyJSON(sources: "").replacingUTF8("tachiyomi-all.example-v1.4.50.apk", with: "../escape.apk")
        ]
        for bytes in invalidJSON {
            #expect(throws: (any Error).self) { try MihonRepositoryCatalog.parse(bytes, indexURL: indexURL) }
        }
        #expect(throws: (any Error).self) {
            try MihonRepositoryCatalog.parse(modernJSON(package: "\(packageJSON),\(packageJSON)"), indexURL: indexURL)
        }
        let ambiguous = Data("""
          {"name":"X","badgeLabel":"X","signingKey":"X","contact":{},"extensionList":{"extensions":[]},"extensionListUrl":"other.pb"}
          """.utf8)
        #expect(throws: (any Error).self) { try MihonRepositoryCatalog.parse(ambiguous, indexURL: indexURL) }
        #expect(throws: (any Error).self) {
            try MihonRepositoryCatalog.parse(legacyJSON(sources: ""), indexURL: URL(string: "javascript:alert(1)")!)
        }
    }

    private var packageJSON: String {
        """
        {"name":"Example","packageName":"example.extension","resources":{"apkUrl":"apk/example.apk","jarUrl":"jar/example.jar","iconUrl":"https://images.example.invalid/example.png"},"extensionLib":"1.6","versionCode":7,"versionName":"1.6.7","contentWarning":"CONTENT_WARNING_MIXED","sources":[{"id":"9007199254740993","name":"English","language":"en","homeUrl":"https://books.example.invalid","mirrorUrls":["https://mirror.example.invalid"]},{"id":42,"name":"Japanese","language":"ja"}]}
        """
    }

    private func legacyJSON(sources: String) -> Data {
        Data("""
        [{"name":"Tachiyomi: Example","pkg":"eu.kanade.tachiyomi.extension.all.example","apk":"tachiyomi-all.example-v1.4.50.apk","lang":"all","code":50,"version":"1.4.50","nsfw":0,"sources":[\(sources)]}]
        """.utf8)
    }

    private func modernJSON(package: String) -> Data {
        Data("""
        {"name":"Example Store","badgeLabel":"EX","signingKey":"unverified-test-key","contact":{"website":"https://example.invalid"},"extensionList":{"extensions":[\(package)]}}
        """.utf8)
    }

    // Synthetic wire fixtures follow the upstream schema. No upstream catalog,
    // extension executable or provider content is copied into this target.
    private func protobufIndex(name: String = "Example Store") -> Data {
        field(1, name) + field(2, "EX") + field(3, "unverified-test-key")
            + field(4, field(1, "https://example.invalid"))
            + field(101, field(1, protobufPackage()))
            + integer(700, 1)
    }

    private func protobufPackage() -> Data {
        let source = integer(1, UInt64(Int64.max)) + field(2, "Example") + field(3, "pt-BR")
            + field(4, "https://books.example.invalid") + field(7, "Test-only fixture")
        let resources = field(1, "apk/example.apk") + field(2, "icon/example.png") + field(501, "jar/example.jar")
        return field(1, "Example") + field(2, "example.extension") + field(3, resources)
            + field(4, "1.6") + integer(5, 7) + field(6, "1.6.7") + integer(7, 99) + field(8, source)
    }

    private func varint(_ input: UInt64) -> Data {
        var input = input, bytes = Data()
        while input >= 128 { bytes.append(UInt8(input & 127) | 128); input >>= 7 }
        bytes.append(UInt8(input)); return bytes
    }
    private func integer(_ field: UInt64, _ value: UInt64) -> Data { varint(field << 3) + varint(value) }
    private func field(_ number: UInt64, _ value: String) -> Data { field(number, Data(value.utf8)) }
    private func field(_ number: UInt64, _ value: Data) -> Data { varint((number << 3) | 2) + varint(UInt64(value.count)) + value }

    private func gzip(_ data: Data) throws -> Data {
        var stream = z_stream()
        guard deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, MAX_WBITS + 16, 8,
            Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw MihonRepositoryCatalog.ParseError.malformedGzip
        }
        defer { deflateEnd(&stream) }
        return try data.withUnsafeBytes { input in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(input.count)
            var result = Data(), buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let status = buffer.withUnsafeMutableBytes { output -> Int32 in
                    stream.next_out = output.bindMemory(to: Bytef.self).baseAddress; stream.avail_out = uInt(output.count)
                    return deflate(&stream, Z_FINISH)
                }
                result.append(contentsOf: buffer.prefix(buffer.count - Int(stream.avail_out)))
                if status == Z_STREAM_END { return result }
                guard status == Z_OK else { throw MihonRepositoryCatalog.ParseError.malformedGzip }
            }
        }
    }
}

private extension Data {
    func replacingUTF8(_ old: String, with new: String) -> Data {
        Data(String(decoding: self, as: UTF8.self).replacingOccurrences(of: old, with: new).utf8)
    }
}
