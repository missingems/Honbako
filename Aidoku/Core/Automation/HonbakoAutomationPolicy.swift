#if SUMI
import Darwin
import Foundation

enum HonbakoAutomationPolicy {
    enum Failure: Error { case invalidJob }

    static func endpoint(_ value: String) -> URL? {
        guard var components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let rawHost = components.host, !rawHost.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true else { return nil }
        let path = components.percentEncodedPath.removingPercentEncoding ?? components.percentEncodedPath
        guard !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == "." || $0 == ".." }),
              !path.contains("\\") else { return nil }
        let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard scheme == "https" || localHost(host) else { return nil }
        components.scheme = scheme
        components.host = rawHost.lowercased()
        while components.percentEncodedPath.hasSuffix("/") { components.percentEncodedPath.removeLast() }
        return components.url
    }

    private static func localHost(_ host: String) -> Bool {
        if host == "localhost" || (host.hasSuffix(".local") && host.count > 6) { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 4, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
           let a = Int(parts[0]), let b = Int(parts[1]), let c = Int(parts[2]), let d = Int(parts[3]),
           [a, b, c, d].allSatisfy({ (0...255).contains($0) }),
           zip(parts, [a, b, c, d]).allSatisfy({ String($0.1) == $0.0 }) {
            return a == 127 || a == 10 || (a == 172 && (16...31).contains(b))
                || (a == 192 && b == 168) || (a == 169 && b == 254)
        }
        var address = in6_addr()
        guard host.withCString({ inet_pton(AF_INET6, $0, &address) }) == 1 else { return false }
        return withUnsafeBytes(of: address) { bytes in
            let loopback = bytes.prefix(15).allSatisfy { $0 == 0 } && bytes[15] == 1
            return loopback || (bytes[0] & 0xfe == 0xfc) || (bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80)
        }
    }

    static func validIdentifier(_ value: String) -> Bool {
        value.range(of: #"\A[A-Za-z0-9_-]{1,128}\z"#, options: .regularExpression) != nil
    }
    static func validDeviceToken(_ value: String) -> Bool {
        value.range(of: #"\A[A-Za-z0-9_-]{20,200}\z"#, options: .regularExpression) != nil
    }
    static func validItem(_ item: HonbakoAutomationModels.Item) -> Bool {
        validText(item.sourceId, maximum: 256) && validText(item.mangaId, maximum: 2048)
            && exportableIdentifier(item.sourceId) && exportableIdentifier(item.mangaId)
    }
    static func exportableIdentifier(_ value: String) -> Bool {
        guard !value.contains("?"), !value.contains("#"),
              let components = URLComponents(string: value),
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { return false }
        return true
    }
    private static func validText(_ value: String, maximum: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= maximum
            && value.rangeOfCharacter(from: .controlCharacters) == nil
    }
    static func validate(_ job: HonbakoAutomationModels.Job) throws {
        guard validIdentifier(job.id), ["queued", "awaitingApproval"].contains(job.status) else { throw Failure.invalidJob }
        if !["history.read", "sources.catalog", "sources.change"].contains(job.kind) {
            guard job.payload.change == nil, job.payload.offset == nil, job.payload.before == nil else { throw Failure.invalidJob }
        }
        switch job.kind {
        case "history.read", "sources.catalog":
            guard (1...100).contains(job.payload.limit ?? 0), (0...2_147_483_646).contains(job.payload.offset ?? -1),
                  job.payload.items == nil, job.payload.query == nil, job.payload.sourceIds == nil,
                  job.payload.idempotencyKey == nil, job.payload.change == nil else { throw Failure.invalidJob }
            if job.kind == "history.read" {
                guard let before = job.payload.before,
                      (try? Date(before, strategy: .iso8601)) != nil || (try? Date(before, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))) != nil
                else { throw Failure.invalidJob }
            } else if job.payload.before != nil { throw Failure.invalidJob }
        case "sources.change":
            guard let change = job.payload.change, let key = job.payload.idempotencyKey, validIdentifier(key),
                  job.payload.items == nil, job.payload.query == nil, job.payload.sourceIds == nil,
                  job.payload.offset == nil, job.payload.before == nil, job.payload.limit == nil else { throw Failure.invalidJob }
            try change.validate()
        case "catalog.search":
            guard let query = job.payload.query, validText(query, maximum: 300),
                  (1...20).contains(job.payload.limit ?? 20),
                  job.payload.items == nil, job.payload.idempotencyKey == nil,
                  job.payload.sourceIds.map({ !$0.isEmpty && $0.count <= 20 && $0.allSatisfy { validText($0, maximum: 256) } }) ?? true
            else { throw Failure.invalidJob }
        case "library.add", "library.remove":
            guard let items = job.payload.items, !items.isEmpty, items.count <= 20,
                  items.allSatisfy(validItem), Set(items).count == items.count,
                  let key = job.payload.idempotencyKey, validIdentifier(key),
                  job.payload.query == nil, job.payload.sourceIds == nil, job.payload.limit == nil
            else { throw Failure.invalidJob }
        default: throw Failure.invalidJob
        }
    }

    static func reading(sourceId: String, mangaId: String, title: String, chapterId: String, chapterTitle: String,
                        chapterNumber: Float? = nil, volumeNumber: Float? = nil, page: Int,
                        totalPages: Int? = nil, lastVisiblePage: Int? = nil,
                        updatedAt: String, active: Bool) -> HonbakoAutomationModels.Reading? {
        guard validItem(.init(sourceId: sourceId, mangaId: mangaId)), validText(chapterId, maximum: 2048), exportableIdentifier(chapterId),
              page >= 1, totalPages.map({ $0 >= page }) ?? true,
              lastVisiblePage.map({ $0 >= page && $0 <= (totalPages ?? Int.max) }) ?? true,
              chapterNumber.map(\.isFinite) ?? true, volumeNumber.map(\.isFinite) ?? true else { return nil }
        return .init(sourceId: sourceId, mangaId: mangaId, title: String(title.prefix(500)),
            chapterId: chapterId, chapterTitle: String(chapterTitle.prefix(500)), chapterNumber: chapterNumber,
            volumeNumber: volumeNumber, page: page, totalPages: totalPages, lastVisiblePage: lastVisiblePage,
            updatedAt: updatedAt, active: active)
    }
}
#endif
