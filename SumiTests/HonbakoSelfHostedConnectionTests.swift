@testable import Sumi
import Foundation
import Testing

@Suite(.serialized)
struct HonbakoSelfHostedConnectionTests {
    @Test("Server identities preserve proxy paths and normalize scheme, host, ports, and slashes")
    func canonicalServerURL() throws {
        let address = try #require(SelfHostedServerURL(" \nHTTPS://Books.Example:443/comics%20archive///\n"))
        #expect(address.url.absoluteString == "https://books.example/comics%20archive/")
        #expect(address.sourceString == "https://books.example/comics%20archive")
        #expect(SelfHostedServerURL("http://EXAMPLE.com:80/")?.sourceString == "http://example.com")
        #expect(SelfHostedServerURL("http://127.0.0.1:8878/komga")?.url.absoluteString == "http://127.0.0.1:8878/komga/")
        #expect(SelfHostedServerURL("http://[::1]:8878/komga/") != nil)
        #expect(URL(string: "api/graphql", relativeTo: address.url)?.absoluteString == "https://books.example/comics%20archive/api/graphql")
    }

    @Test("Connection addresses require HTTP(S), a host, and no embedded credentials or unrelated URL suffixes")
    func rejectInvalidServerURLs() {
        for value in ["", "books.example/komga", "/komga", "file:///komga", "ftp://books.example/", "https:///", "https://user:password@books.example/", "https://books.example/?apiKey=secret", "https://books.example/#reader", "http://books.example:0/"] {
            #expect(SelfHostedServerURL(value) == nil, "Must reject: \(value)")
        }
    }

    @Test("Suwayomi auth discovery keeps a reverse proxy prefix when the entered URL has no final slash")
    func suwayomiProxyPath() async throws {
        let fixture = SelfHostedTransportFixture { request in
            switch (request.httpMethod, request.url?.path) {
                case ("GET", "/proxy/suwayomi"): return .init(status: 200, body: "ready")
                case ("POST", "/proxy/suwayomi/api/graphql"): return .init(status: 200, body: #"{"data":{"settings":{"authMode":"NONE"}}}"#)
                default: throw URLError(.badURL)
            }
        }
        let session = fixture.makeSession()
        defer { session.invalidateAndCancel(); fixture.remove() }
        let server = try #require(URL(string: fixture.origin + "/proxy/suwayomi"))
        let type = await SuwayomiHelper.getLoginType(server: server, session: session)
        if case .none? = type {} else { Issue.record("Expected the server's no-auth mode") }
        #expect(fixture.requests.map { $0.url?.path ?? "" } == ["/proxy/suwayomi", "/proxy/suwayomi/api/graphql"])
    }

    @Test("Suwayomi simple login sends user/pass fields and preserves literal plus signs in credentials")
    func suwayomiSimpleLogin() async throws {
        let fixture = SelfHostedTransportFixture { request in
            if request.httpMethod == "GET" {
                return .init(status: 302, body: "", headers: ["Location": "/proxy/suwayomi/login.html"])
            }
            return .init(status: 303, body: "", headers: ["Location": "/proxy/suwayomi/", "Set-Cookie": "JSESSIONID=fixture-session; Path=/proxy/suwayomi/; HttpOnly"])
        }
        let session = fixture.makeSession()
        defer { session.invalidateAndCancel(); fixture.remove() }
        let server = try #require(URL(string: fixture.origin + "/proxy/suwayomi"))
        let login = await SuwayomiHelper.checkLogin(server: server, username: "reader+fixture", password: "test+pass&word=only", session: session)
        #expect(login?.cookie == "JSESSIONID=fixture-session")
        let request = try #require(fixture.requests.last)
        #expect(request.url?.path == "/proxy/suwayomi/login.html")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        let body = try #require(request.httpBody)
        let form = try #require(String(data: body, encoding: .utf8))
        let fields = Dictionary(uniqueKeysWithValues: form.split(separator: "&").map { field -> (String, String) in
            let parts = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let decode: (Substring) -> String = { String($0).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? "" }
            return (decode(parts[0]), parts.count > 1 ? decode(parts[1]) : "")
        })
        #expect(fields == ["user": "reader+fixture", "pass": "test+pass&word=only"])
    }

    @Test("A simple-login error page with Set-Cookie cannot establish an authenticated connection")
    func suwayomiRejectsErrorPageCookie() async throws {
        let fixture = SelfHostedTransportFixture { request in
            if request.httpMethod == "GET" {
                return .init(status: 302, body: "", headers: ["Location": "/proxy/suwayomi/login.html"])
            }
            return .init(status: 200, body: "Invalid username or password", headers: ["Set-Cookie": "JSESSIONID=unauthenticated; Path=/proxy/suwayomi/; HttpOnly"])
        }
        let session = fixture.makeSession()
        defer { session.invalidateAndCancel(); fixture.remove() }
        let server = try #require(URL(string: fixture.origin + "/proxy/suwayomi"))
        let login = await SuwayomiHelper.checkLogin(server: server, username: "reader", password: "wrong", session: session)
        #expect(login == nil)
        #expect(fixture.requests.count == 2)
    }

    @Test("Simple login requires a success redirect to this server's configured root")
    func suwayomiRejectsUnexpectedLoginRedirect() async throws {
        for target in ["/proxy/suwayomi/login.html", "http://another-server.invalid/", "/"] {
            let fixture = SelfHostedTransportFixture { request in
                if request.httpMethod == "GET" {
                    return .init(status: 302, body: "", headers: ["Location": "/proxy/suwayomi/login.html"])
                }
                return .init(status: 303, body: "", headers: ["Location": target, "Set-Cookie": "JSESSIONID=unexpected; Path=/proxy/suwayomi/; HttpOnly"])
            }
            let session = fixture.makeSession()
            defer { session.invalidateAndCancel(); fixture.remove() }
            let server = try #require(URL(string: fixture.origin + "/proxy/suwayomi"))
            let login = await SuwayomiHelper.checkLogin(server: server, username: "reader", password: "password", session: session)
            #expect(login == nil, "Must reject unexpected redirect: \(target)")
        }
    }

    @Test("A rejected Basic login does not create a successful connection")
    func suwayomiRejectsBadCredentials() async throws {
        let fixture = SelfHostedTransportFixture { _ in .init(status: 401, body: "Unauthorized") }
        let session = fixture.makeSession()
        defer { session.invalidateAndCancel(); fixture.remove() }
        let server = try #require(URL(string: fixture.origin + "/suwayomi"))
        let login = await SuwayomiHelper.checkLogin(server: server, username: "reader", password: "wrong", session: session)
        #expect(login == nil)
        #expect(fixture.requests.count == 2)
        #expect(fixture.requests.last?.value(forHTTPHeaderField: "Authorization") == "Basic " + Data("reader:wrong".utf8).base64EncodedString())
    }

    @Test("HTTP failure cannot masquerade as a successful GraphQL auth response")
    func suwayomiRejectsHTTPFailure() async throws {
        let fixture = SelfHostedTransportFixture { request in
            if request.httpMethod == "GET" { return .init(status: 200, body: "ready") }
            return .init(status: 503, body: #"{"data":{"settings":{"authMode":"NONE"}}}"#)
        }
        let session = fixture.makeSession()
        defer { session.invalidateAndCancel(); fixture.remove() }
        let server = try #require(URL(string: fixture.origin))
        #expect(await SuwayomiHelper.getLoginType(server: server, session: session) == nil)
    }

    @Test("Kavita mirror URLs retain the proxy prefix for relative API requests")
    func kavitaMirrorPaths() throws {
        let key = "honbako-selfhost-fixture-\(UUID())"
        UserDefaults.standard.set(["https://mirror.example/kavita", "not a URL"], forKey: "\(key).mirrors")
        defer { UserDefaults.standard.removeObject(forKey: "\(key).mirrors") }
        let mirrors = KavitaHelper(sourceKey: key).getMirrors()
        #expect(mirrors.count == 1)
        let mirror = try #require(mirrors.first)
        #expect(URL(string: "api/Series/all-v2", relativeTo: mirror)?.absoluteString == "https://mirror.example/kavita/api/Series/all-v2")
    }
}

/// Only these ephemeral sessions can use the fixture. No shared URLSession or live endpoint is intercepted.
private final class SelfHostedTransportFixture: @unchecked Sendable {
    struct Response: Sendable {
        let status: Int
        let body: String
        var headers: [String: String] = ["Content-Type": "application/json"]
    }
    typealias Handler = @Sendable (URLRequest) throws -> Response
    let host = "selfhost-\(UUID().uuidString.lowercased()).invalid"
    var origin: String { "http://" + host }
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private let handler: Handler
    init(handler: @escaping Handler) {
        self.handler = handler
        SelfHostedFixtureProtocol.registry.add(self)
    }
    var requests: [URLRequest] { lock.withLock { recorded } }
    func respond(to request: URLRequest) throws -> Response {
        var request = request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count >= 0 else { throw URLError(.cannotDecodeRawData) }
                if count == 0 { break }
                data.append(contentsOf: buffer.prefix(count))
                guard data.count <= 1_048_576 else { throw URLError(.dataLengthExceedsMaximum) }
            }
            request.httpBody = data
        }
        lock.withLock { recorded.append(request) }
        return try handler(request)
    }
    func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SelfHostedFixtureProtocol.self]
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }
    func remove() { SelfHostedFixtureProtocol.registry.remove(host: host) }
}

private final class SelfHostedFixtureRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var fixtures: [String: SelfHostedTransportFixture] = [:]
    func add(_ fixture: SelfHostedTransportFixture) { lock.withLock { fixtures[fixture.host] = fixture } }
    func remove(host: String) { lock.withLock { _ = fixtures.removeValue(forKey: host) } }
    func fixture(for host: String?) -> SelfHostedTransportFixture? { lock.withLock { fixtures[host ?? ""] } }
}

private final class SelfHostedFixtureProtocol: URLProtocol, @unchecked Sendable {
    static let registry = SelfHostedFixtureRegistry()
    override class func canInit(with request: URLRequest) -> Bool { registry.fixture(for: request.url?.host) != nil }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let fixture = Self.registry.fixture(for: request.url?.host), let url = request.url else { throw URLError(.unsupportedURL) }
            let result = try fixture.respond(to: request)
            guard let response = HTTPURLResponse(url: url, statusCode: result.status, httpVersion: "HTTP/1.1", headerFields: result.headers) else { throw URLError(.badServerResponse) }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(result.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}
