@testable import Sumi
import Testing

@MainActor
@Suite(.serialized)
struct SumiSourceBootstrapTests {
    @Test("Fresh source setup loads no predefined catalog or provider")
    func noBundledSources() async {
        let bootstrap = SumiCatalogBootstrap(sourceLoader: { [] })
        await bootstrap.prepare()
        #expect(bootstrap.state == .ready)
        #expect(bootstrap.availableSourceKeys.isEmpty)
        #expect(bootstrap.failures.isEmpty)
    }

    @Test("Source setup reflects only already connected sources and reloads changes")
    func reflectsManualConnections() async {
        let connections = Connections()
        let bootstrap = SumiCatalogBootstrap(sourceLoader: { connections.keys })
        connections.keys = ["my-komga", "my-custom-source"]
        await bootstrap.prepare()
        #expect(bootstrap.availableSourceKeys == ["my-custom-source", "my-komga"])
        connections.keys = ["my-komga"]
        await bootstrap.prepare()
        #expect(bootstrap.availableSourceKeys == ["my-komga"])
    }

    @MainActor private final class Connections { var keys: [String] = [] }
}
