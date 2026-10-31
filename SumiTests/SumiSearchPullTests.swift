@testable import Sumi
import Foundation
import Testing

struct SumiSearchPullTests {
    @Test("The ordinary scroll range has one stable zero value, including adjusted top insets")
    func ordinaryOffsetsStayZero() {
        for offset in [-92.0, -60, 0, 20, 600, 20_000] {
            #expect(SumiSearchPull.distance(contentOffset: offset, topInset: 92) == 0)
        }
    }

    @Test("Top overscroll follows the finger and caps at the reveal threshold")
    func boundedOverscroll() {
        #expect(SumiSearchPull.distance(contentOffset: -105, topInset: 92) == 13)
        #expect(SumiSearchPull.distance(contentOffset: -1_000, topInset: 92) == 52)
        #expect(SumiSearchPull.progress(distance: 13) == 0.25)
        #expect(SumiSearchPull.progress(distance: 1_000) == 1)
        #expect(SumiSearchPull.distance(contentOffset: -92, topInset: 92) == 0)
    }
}
