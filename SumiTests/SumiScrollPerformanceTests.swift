@testable import Sumi
import AidokuRunner
import Combine
import UIKit
import XCTest

@MainActor
final class SumiScrollPerformanceTests: XCTestCase {
    func testColdCoverTileLayoutCost() {
        let books = (0..<60).map { index in
            SumiBook(manga: .init(sourceKey: "scroll-benchmark", key: "book-\(index)",
                title: "The Bookshop Between Pages \(index)"))
        }
        let warmup = SumiGridBookView(frame: CGRect(x: 0, y: 0, width: 150, height: 220))
        warmup.configure(book: books[0])
        warmup.layoutIfNeeded()
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            for book in books {
                autoreleasepool {
                    let tile = SumiGridBookView(frame: .zero)
                    tile.configure(book: book)
                    tile.frame = CGRect(x: 0, y: 0, width: 150, height: 220)
                    tile.setNeedsLayout()
                    tile.layoutIfNeeded()
                    XCTAssertNotNil(tile.image)
                    XCTAssertEqual(tile.image?.size, tile.bounds.size)
                }
            }
        }
    }

    func testOrdinaryScrollPublicationCount() throws {
        let search = SumiSearchPresentation()
        var publications = 0
        let observation = search.objectWillChange.sink { publications += 1 }
        for _ in 0..<600 { search.updatePull(distance: 0) }
        withExtendedLifetime(observation) {}
        let report: [String: Int] = ["ordinaryScrollCallbacks": 600, "searchPublications": publications]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: .sortedKeys),
            uniformTypeIdentifier: "public.json")
        attachment.name = "ordinary-scroll-publications.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("Honbako scroll benchmark: \(publications) search publications for 600 ordinary scroll callbacks")
    }
}
