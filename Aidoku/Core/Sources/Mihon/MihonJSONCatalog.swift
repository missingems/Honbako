import Foundation

/// Independently implemented from the public schema; provenance is in SCHEMA.md.
enum MihonJSONCatalog {
    typealias Catalog = MihonRepositoryCatalog

    static func parse(_ data: Data, indexURL: URL) throws -> Catalog {
        let decoder = JSONDecoder()
        let legacy: [LegacyPackage]?
        let modern: Index?
        do {
            legacy = try? decoder.decode([LegacyPackage].self, from: data)
            modern = legacy == nil ? try decoder.decode(Index.self, from: data) : nil
        } catch { throw Catalog.ParseError.malformedJSON }
        if let legacy {
            let packages = try legacy.map { try $0.into(relativeTo: indexURL) }
            try Catalog.validate(packages)
            return Catalog(indexURL: indexURL, format: .legacyJSON, metadata: nil, packages: packages, extensionListURL: nil)
        }
        guard let modern else { throw Catalog.ParseError.malformedJSON }
        guard !modern.name.isEmpty, (modern.extensionList != nil) != (modern.extensionListUrl?.isEmpty == false) else {
            throw Catalog.ParseError.invalidField("extensionList/extensionListUrl")
        }
        let packages = try modern.extensionList?.extensions.map { try $0.into(relativeTo: indexURL) } ?? []
        try Catalog.validate(packages)
        return try Catalog(indexURL: indexURL, format: .json,
            metadata: .init(name: modern.name, badgeLabel: modern.badgeLabel, signingKey: modern.signingKey,
                contact: .init(website: Catalog.resolvedURL(modern.contact.website, relativeTo: indexURL, metadata: true),
                    discord: Catalog.resolvedURL(modern.contact.discord, relativeTo: indexURL, metadata: true))),
            packages: packages, extensionListURL: Catalog.resolvedURL(modern.extensionListUrl, relativeTo: indexURL))
    }

    static func parseExtensionList(_ data: Data, url: URL) throws -> [Catalog.Package] {
        let list: ExtensionList
        do { list = try JSONDecoder().decode(ExtensionList.self, from: data) }
        catch { throw Catalog.ParseError.malformedJSON }
        return try list.extensions.map { try $0.into(relativeTo: url) }
    }

    private struct ExactID: Decodable {
        let number: Int64
        var value: String { String(number) }
        static let zero = ExactID(number: 0)
        private init(number: Int64) { self.number = number }
        init(from decoder: Decoder) throws {
            let single = try decoder.singleValueContainer()
            if let string = try? single.decode(String.self) {
                let canonical = try Catalog.exactID(string)
                guard let parsed = Int64(canonical) else { throw Catalog.ParseError.invalidField("int64") }
                number = parsed
            } else { number = try single.decode(Int64.self) }
        }
    }

    private struct LegacyPackage: Decodable {
        let name: String
        let pkg: String
        let apk: String
        let lang: String
        let code: Int64
        let version: String
        let nsfw: Int?
        let sources: [LegacySource]?

        func into(relativeTo indexURL: URL) throws -> Catalog.Package {
            // Legacy names are filenames below apk/, not arbitrary remote URLs.
            guard !apk.isEmpty, apk == URL(fileURLWithPath: apk).lastPathComponent,
                  !apk.contains("\\"), !apk.contains("%"), !apk.contains("?"), !apk.contains("#"),
                  apk.lowercased().hasSuffix(".apk") else { throw Catalog.ParseError.invalidField("apk") }
            let versionParts = version.split(separator: ".", omittingEmptySubsequences: false)
            let library = versionParts.dropLast().joined(separator: ".")
            return try .init(name: name, packageName: pkg, extensionLib: library,
                versionCode: code, versionName: version, language: lang,
                contentWarning: nsfw == 1 ? 3 : 1,
                iconURL: Catalog.resolvedURL("icon/\(pkg).png", relativeTo: indexURL),
                artifacts: [.init(format: .androidAPK, url: Catalog.requiredURL("apk/\(apk)", relativeTo: indexURL))],
                sources: sources?.map { try $0.into(relativeTo: indexURL) } ?? [])
        }
    }

    private struct LegacySource: Decodable {
        let id: ExactID
        let name: String
        let lang: String
        let baseUrl: String?
        let versionId: Int64?
        func into(relativeTo url: URL) throws -> Catalog.Source {
            try .init(id: id.value, name: name, language: lang,
                homeURL: Catalog.resolvedURL(baseUrl, relativeTo: url, metadata: true), mirrorURLs: [], message: nil, versionID: versionId)
        }
    }

    private struct Index: Decodable {
        let name: String
        let badgeLabel: String
        let signingKey: String
        let contact: Contact
        let extensionList: ExtensionList?
        let extensionListUrl: String?

        private enum CodingKeys: String, CodingKey { case name, badgeLabel, signingKey, contact, extensionList, extensionListUrl }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
            badgeLabel = try values.decodeIfPresent(String.self, forKey: .badgeLabel) ?? ""
            signingKey = try values.decodeIfPresent(String.self, forKey: .signingKey) ?? ""
            contact = try values.decodeIfPresent(Contact.self, forKey: .contact) ?? .init(website: nil, discord: nil)
            extensionList = try values.decodeIfPresent(ExtensionList.self, forKey: .extensionList)
            extensionListUrl = try values.decodeIfPresent(String.self, forKey: .extensionListUrl)
        }
    }
    private struct Contact: Decodable { let website: String?; let discord: String? }
    private struct ExtensionList: Decodable {
        let extensions: [Package]
        private enum CodingKeys: String, CodingKey { case extensions }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            extensions = try values.decodeIfPresent([Package].self, forKey: .extensions) ?? []
        }
    }
    private struct Resources: Decodable { let apkUrl: String?; let iconUrl: String?; let jarUrl: String? }

    private struct Warning: Decodable {
        let rawValue: Int64
        init(rawValue: Int64) { self.rawValue = rawValue }
        init(from decoder: Decoder) throws {
            let single = try decoder.singleValueContainer()
            if let number = try? single.decode(Int64.self) { rawValue = number; return }
            let string = try single.decode(String.self)
            switch string {
                case "UNSPECIFIED", "CONTENT_WARNING_UNSPECIFIED": rawValue = 0
                case "SAFE", "CONTENT_WARNING_SAFE": rawValue = 1
                case "MIXED", "CONTENT_WARNING_MIXED": rawValue = 2
                case "NSFW", "CONTENT_WARNING_NSFW": rawValue = 3
                default: throw Catalog.ParseError.invalidField("contentWarning")
            }
        }
    }

    private struct Package: Decodable {
        let name: String
        let packageName: String
        let resources: Resources
        let extensionLib: String
        let versionCode: Int64
        let versionName: String
        let contentWarning: Warning
        let sources: [Source]

        private enum CodingKeys: String, CodingKey {
            case name, packageName, resources, extensionLib, versionCode, versionName, contentWarning, sources
        }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
            packageName = try values.decodeIfPresent(String.self, forKey: .packageName) ?? ""
            resources = try values.decodeIfPresent(Resources.self, forKey: .resources) ?? .init(apkUrl: nil, iconUrl: nil, jarUrl: nil)
            extensionLib = try values.decodeIfPresent(String.self, forKey: .extensionLib) ?? ""
            versionCode = try values.decodeIfPresent(ExactID.self, forKey: .versionCode)?.number ?? 0
            versionName = try values.decodeIfPresent(String.self, forKey: .versionName) ?? ""
            contentWarning = try values.decodeIfPresent(Warning.self, forKey: .contentWarning) ?? .init(rawValue: 0)
            sources = try values.decodeIfPresent([Source].self, forKey: .sources) ?? []
        }

        func into(relativeTo url: URL) throws -> Catalog.Package {
            var artifacts: [Catalog.Artifact] = []
            if let apk = try Catalog.resolvedURL(resources.apkUrl, relativeTo: url) {
                artifacts.append(.init(format: .androidAPK, url: apk))
            }
            if let jar = try Catalog.resolvedURL(resources.jarUrl, relativeTo: url) {
                artifacts.append(.init(format: .javaArchive, url: jar))
            }
            let languages = Set(sources.map(\.language))
            return try .init(name: name, packageName: packageName, extensionLib: extensionLib,
                versionCode: versionCode, versionName: versionName,
                language: languages.count == 1 ? languages.first! : "all", contentWarning: contentWarning.rawValue,
                iconURL: Catalog.resolvedURL(resources.iconUrl, relativeTo: url), artifacts: artifacts,
                sources: sources.map { try $0.into(relativeTo: url) })
        }
    }

    private struct Source: Decodable {
        let id: ExactID
        let name: String
        let language: String
        let homeUrl: String?
        let mirrorUrls: [String]?
        let message: String?

        private enum CodingKeys: String, CodingKey { case id, name, language, homeUrl, mirrorUrls, message }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decodeIfPresent(ExactID.self, forKey: .id) ?? ExactID.zero
            name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
            language = try values.decodeIfPresent(String.self, forKey: .language) ?? ""
            homeUrl = try values.decodeIfPresent(String.self, forKey: .homeUrl)
            mirrorUrls = try values.decodeIfPresent([String].self, forKey: .mirrorUrls)
            message = try values.decodeIfPresent(String.self, forKey: .message)
        }
        func into(relativeTo url: URL) throws -> Catalog.Source {
            try .init(id: id.value, name: name, language: language,
                homeURL: Catalog.resolvedURL(homeUrl, relativeTo: url, metadata: true),
                mirrorURLs: (mirrorUrls ?? []).map { try Catalog.requiredURL($0, relativeTo: url, metadata: true) },
                message: message, versionID: nil)
        }
    }
}
