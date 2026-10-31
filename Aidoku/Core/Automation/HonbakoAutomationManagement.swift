#if SUMI
import Foundation

enum HonbakoAutomationManagement {
    struct Change: Codable, Equatable, Sendable {
        let action: String
        var sourceId: String?
        var repositoryURL: String?

        var title: String {
            switch action {
            case "install": "Install Extension"
            case "enable": "Enable Source"
            case "disable": "Disable Source"
            case "remove": "Remove Source"
            case "add_repository": "Add Extension Repository"
            case "remove_repository": "Remove Extension Repository"
            default: "Refresh Extension Repositories"
            }
        }
        func validate() throws {
            switch action {
            case "install", "enable", "disable", "remove":
                guard let sourceId, repositoryURL == nil,
                      HonbakoAutomationPolicy.validItem(.init(sourceId: sourceId, mangaId: "source")) else {
                    throw HonbakoAutomationPolicy.Failure.invalidJob
                }
            case "add_repository", "remove_repository":
                guard sourceId == nil, let repositoryURL, Self.safeRepository(repositoryURL) != nil else {
                    throw HonbakoAutomationPolicy.Failure.invalidJob
                }
            case "refresh_repositories":
                guard sourceId == nil, repositoryURL == nil else { throw HonbakoAutomationPolicy.Failure.invalidJob }
            default: throw HonbakoAutomationPolicy.Failure.invalidJob
            }
        }
        static func safeRepository(_ text: String) -> URL? {
            guard text.utf8.count <= 2048, let components = URLComponents(string: text), components.scheme == "https",
                  components.host?.isEmpty == false, components.user == nil, components.password == nil,
                  components.query == nil, components.fragment == nil else { return nil }
            return components.url
        }
    }
    struct CatalogSource: Codable, Sendable {
        let sourceId: String
        let name: String
        let installed: Bool
        let disabled: Bool
        var repositoryURL: String?
    }
    struct Repository: Codable, Sendable {
        let url: String
        let name: String
        let available: Bool
    }
    struct Catalog: Codable, Sendable {
        let sources: [CatalogSource]
        let repositories: [Repository]
        let nextOffset: Int?
        let observedAt: String
    }
    struct Result: Codable, Sendable {
        let change: Change
        var applied = true
        let observedAt: String
    }
}
#endif
