@testable import Sumi
import Testing

struct HonbakoSourceCompatibilityTests {
    @Test("A new product version does not hide compatible reader-engine sources")
    func independentEngineVersion() {
        let version = SourcePackageCompatibility.configuredVersion(in: [
            "CFBundleShortVersionString": "0.1.0", "SourceEngineVersion": "0.9.0"
        ])
        #expect(version == "0.9.0")
        #expect(SourcePackageCompatibility.supports(minimum: "0.7.2", maximum: nil, version: version))
        #expect(!SourcePackageCompatibility.supports(minimum: "0.10", maximum: nil, version: version))
        #expect(!SourcePackageCompatibility.supports(minimum: nil, maximum: "0.8", version: version))
    }

    @Test("An original reader build keeps using its own version when no override exists")
    func originalReaderFallback() {
        #expect(SourcePackageCompatibility.configuredVersion(in: ["CFBundleShortVersionString": "0.9"]) == "0.9")
    }
}
