import Foundation

/// Minimal bounded decoder for the published tachiyomix index schema. It does
/// not execute extensions. Unknown protobuf fields are skipped by wire type.
enum MihonProtobufCatalog {
    typealias Catalog = MihonRepositoryCatalog

    static func parse(_ data: Data, indexURL: URL) throws -> Catalog {
        var reader = Reader(data)
        var name = "", badge = "", signingKey = ""
        var contact = Catalog.Contact(website: nil, discord: nil)
        var packages: [Catalog.Package]?
        var listURL: URL?
        while let field = try reader.next() {
            switch field.number {
                case 1: name = try field.string()
                case 2: badge = try field.string()
                case 3: signingKey = try field.string()
                case 4: contact = try parseContact(field.data(), url: indexURL)
                case 101:
                    packages = try parseExtensionList(field.data(), url: indexURL)
                    listURL = nil
                case 102:
                    listURL = try Catalog.requiredURL(field.string(), relativeTo: indexURL)
                    packages = nil
                default: break
            }
        }
        guard !name.isEmpty, packages != nil || listURL != nil else { throw Catalog.ParseError.invalidField("index") }
        try Catalog.validate(packages ?? [])
        return .init(indexURL: indexURL, format: .protobuf,
            metadata: .init(name: name, badgeLabel: badge, signingKey: signingKey, contact: contact),
            packages: packages ?? [], extensionListURL: listURL)
    }

    static func parseExtensionList(_ data: Data, url: URL) throws -> [Catalog.Package] {
        var reader = Reader(data)
        var packages: [Catalog.Package] = []
        while let field = try reader.next() {
            guard field.number == 1 else { continue }
            guard packages.count < Catalog.maximumPackages else { throw Catalog.ParseError.payloadTooLarge }
            packages.append(try parsePackage(field.data(), url: url))
        }
        return packages
    }

    private static func parseContact(_ data: Data, url: URL) throws -> Catalog.Contact {
        var reader = Reader(data)
        var website: URL?, discord: URL?
        while let field = try reader.next() {
            switch field.number {
                case 1: website = try Catalog.resolvedURL(field.string(), relativeTo: url, metadata: true)
                case 2: discord = try Catalog.resolvedURL(field.string(), relativeTo: url, metadata: true)
                default: break
            }
        }
        return .init(website: website, discord: discord)
    }

    private static func parsePackage(_ data: Data, url: URL) throws -> Catalog.Package {
        var reader = Reader(data)
        var name = "", package = "", library = "", version = ""
        var code: Int64 = 0, warning: Int64 = 0
        var icon: URL?
        var artifacts: [Catalog.Artifact] = []
        var sources: [Catalog.Source] = []
        while let field = try reader.next() {
            switch field.number {
                case 1: name = try field.string()
                case 2: package = try field.string()
                case 3: (artifacts, icon) = try parseResources(field.data(), url: url)
                case 4: library = try field.string()
                case 5: code = try field.integer()
                case 6: version = try field.string()
                case 7: warning = try field.integer()
                case 8:
                    guard sources.count < 10_000 else { throw Catalog.ParseError.payloadTooLarge }
                    sources.append(try parseSource(field.data(), url: url))
                default: break
            }
        }
        let languages = Set(sources.map(\.language))
        return .init(name: name, packageName: package, extensionLib: library, versionCode: code,
            versionName: version, language: languages.count == 1 ? languages.first! : "all",
            contentWarning: warning, iconURL: icon, artifacts: artifacts, sources: sources)
    }

    private static func parseResources(_ data: Data, url: URL) throws -> ([Catalog.Artifact], URL?) {
        var reader = Reader(data)
        var apk: URL?, jar: URL?, icon: URL?
        while let field = try reader.next() {
            switch field.number {
                case 1: apk = try Catalog.resolvedURL(field.string(), relativeTo: url)
                case 2: icon = try Catalog.resolvedURL(field.string(), relativeTo: url)
                // Keiyoushi's documented extension to the upstream schema.
                case 501: jar = try Catalog.resolvedURL(field.string(), relativeTo: url)
                default: break
            }
        }
        var artifacts: [Catalog.Artifact] = []
        if let apk { artifacts.append(.init(format: .androidAPK, url: apk)) }
        if let jar { artifacts.append(.init(format: .javaArchive, url: jar)) }
        return (artifacts, icon)
    }

    private static func parseSource(_ data: Data, url: URL) throws -> Catalog.Source {
        var reader = Reader(data)
        var id: Int64 = 0
        var name = "", language = ""
        var home: URL?, message: String?
        var mirrors: [URL] = []
        while let field = try reader.next() {
            switch field.number {
                case 1: id = try field.integer()
                case 2: name = try field.string()
                case 3: language = try field.string()
                case 4: home = try Catalog.resolvedURL(field.string(), relativeTo: url, metadata: true)
                case 5: mirrors.append(try Catalog.requiredURL(field.string(), relativeTo: url, metadata: true))
                case 7: message = try field.string()
                default: break
            }
        }
        return .init(id: String(id), name: name, language: language, homeURL: home,
            mirrorURLs: mirrors, message: message, versionID: nil)
    }

    private struct Field {
        enum Value { case integer(UInt64), bytes(Data), skipped }
        let number: Int
        let value: Value
        func integer() throws -> Int64 {
            guard case .integer(let number) = value else { throw Catalog.ParseError.malformedProtobuf }
            return Int64(bitPattern: number)
        }
        func data() throws -> Data {
            guard case .bytes(let data) = value else { throw Catalog.ParseError.malformedProtobuf }
            return data
        }
        func string() throws -> String {
            guard let value = String(data: try data(), encoding: .utf8) else { throw Catalog.ParseError.malformedProtobuf }
            return value
        }
    }

    private struct Reader {
        let data: Data
        var offset = 0
        var fieldCount = 0
        init(_ data: Data) { self.data = data }

        mutating func next() throws -> Field? {
            guard offset < data.count else { return nil }
            fieldCount += 1
            guard fieldCount <= 200_000 else { throw Catalog.ParseError.payloadTooLarge }
            let key = try varint()
            let number = key >> 3
            guard number > 0, number <= 0x1FFF_FFFF else { throw Catalog.ParseError.malformedProtobuf }
            let value: Field.Value
            switch key & 7 {
                case 0: value = .integer(try varint())
                case 1: try skip(8); value = .skipped
                case 2:
                    let count = try varint()
                    guard count <= UInt64(data.count - offset) else { throw Catalog.ParseError.malformedProtobuf }
                    let end = offset + Int(count)
                    value = .bytes(data.subdata(in: (data.startIndex + offset)..<(data.startIndex + end))); offset = end
                case 5: try skip(4); value = .skipped
                default: throw Catalog.ParseError.malformedProtobuf
            }
            return .init(number: Int(number), value: value)
        }

        private mutating func skip(_ count: Int) throws {
            guard count <= data.count - offset else { throw Catalog.ParseError.malformedProtobuf }
            offset += count
        }

        private mutating func varint() throws -> UInt64 {
            var value: UInt64 = 0
            for byteIndex in 0..<10 {
                guard offset < data.count else { throw Catalog.ParseError.malformedProtobuf }
                let byte = data[data.startIndex + offset]; offset += 1
                guard byteIndex != 9 || byte <= 1 else { throw Catalog.ParseError.malformedProtobuf }
                value |= UInt64(byte & 0x7F) << (byteIndex * 7)
                if byte & 0x80 == 0 { return value }
            }
            throw Catalog.ParseError.malformedProtobuf
        }
    }
}
