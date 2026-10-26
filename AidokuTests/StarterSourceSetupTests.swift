import Testing

@testable import Aidoku

struct StarterSourceSetupTests {
    @Test func installsAndPinsOnlyOnce() async {
        let fixture = StarterSourceFixture()
        await fixture.run()
        await fixture.run()

        #expect(await fixture.installRequests.count == 1)
        #expect(await fixture.completed == Set(StarterSourceFixture.keys))
        #expect(await fixture.pinned.count == StarterSourceFixture.keys.count)
    }

    @Test func retriesOnlyFailedInstallations() async {
        let fixture = StarterSourceFixture(failing: ["manga"])
        await fixture.run()

        #expect(await fixture.completed == ["webtoon"])
        await fixture.setFailing([])
        await fixture.run()

        #expect(await fixture.installRequests == [["manga", "webtoon"], ["manga"]])
        #expect(await fixture.completed == Set(StarterSourceFixture.keys))
    }

    @Test func unavailableCatalogRemainsRetryable() async {
        let fixture = StarterSourceFixture(catalogAvailable: false)
        await fixture.run()

        #expect(await fixture.completed.isEmpty)
        await fixture.setCatalogAvailable(true)
        await fixture.run()

        #expect(await fixture.completed == Set(StarterSourceFixture.keys))
        #expect(await fixture.installRequests.count == 2)
    }

    @Test func alreadyInstalledSourcesArePinnedWithoutDownloading() async {
        let fixture = StarterSourceFixture(installed: Set(StarterSourceFixture.keys))
        await fixture.run()

        #expect(await fixture.installRequests.isEmpty)
        #expect(await fixture.pinned == StarterSourceFixture.keys)
        #expect(await fixture.completed == Set(StarterSourceFixture.keys))
    }

    @Test func removingSourceAfterSetupDoesNotReinstallOrRepinIt() async {
        let fixture = StarterSourceFixture()
        await fixture.run()
        await fixture.removeSource("manga")
        await fixture.run()

        #expect(await fixture.installRequests.count == 1)
        #expect(await !fixture.installed.contains("manga"))
        #expect(await !fixture.pinned.contains("manga"))
    }
}

private actor StarterSourceFixture {
    static let keys = ["manga", "webtoon"]
    var completed: Set<String> = []
    var installed: Set<String>
    var pinned: [String] = []
    var installRequests: [Set<String>] = []
    private var failing: Set<String>
    private var catalogAvailable: Bool

    init(installed: Set<String> = [], failing: Set<String> = [], catalogAvailable: Bool = true) {
        self.installed = installed
        self.failing = failing
        self.catalogAvailable = catalogAvailable
    }

    func run() async {
        await StarterSourceSetup.run(
            keys: Self.keys,
            completed: completed,
            missingSourceKeys: { $0.subtracting(self.installed) },
            installSources: { self.install($0) },
            onCompletion: { self.complete($0) }
        )
    }

    func setFailing(_ keys: Set<String>) { failing = keys }
    func setCatalogAvailable(_ available: Bool) { catalogAvailable = available }

    func removeSource(_ key: String) {
        installed.remove(key)
        pinned.removeAll { $0 == key }
    }

    private func install(_ keys: Set<String>) -> AsyncStream<String>? {
        installRequests.append(keys)
        guard catalogAvailable else { return nil }
        let successes = keys.subtracting(failing)
        installed.formUnion(successes)
        return AsyncStream { continuation in
            for key in successes.sorted() { continuation.yield(key) }
            continuation.finish()
        }
    }

    private func complete(_ key: String) {
        completed.insert(key)
        pinned.append(key)
    }
}
