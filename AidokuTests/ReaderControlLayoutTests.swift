//
//  ReaderControlLayoutTests.swift
//  AidokuTests
//

@testable import Aidoku
import CoreGraphics
import Testing

struct ReaderControlLayoutTests {
    @Test("Book fold moves controls to the nearest usable region")
    func bookFold() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let fold = CGRect(x: 480, y: 0, width: 40, height: 800)
        let control = CGRect(x: 490, y: 720, width: 100, height: 44)
        let offset = ReaderControlLayout.offset(for: control, inside: bounds, avoiding: [fold])
        let result = control.offsetBy(dx: offset.x, dy: offset.y)

        #expect(result.minX == fold.maxX)
        #expect(result.minY == control.minY)
        #expect(bounds.contains(result))
        #expect(!result.intersects(fold))
    }

    @Test("Tabletop controls remain in the lower region when it is closest")
    func tabletopFold() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let fold = CGRect(x: 0, y: 380, width: 1000, height: 40)
        let control = CGRect(x: 800, y: 400, width: 150, height: 44)
        let offset = ReaderControlLayout.offset(for: control, inside: bounds, avoiding: [fold])
        let result = control.offsetBy(dx: offset.x, dy: offset.y)

        #expect(result.minY == fold.maxY)
        #expect(result.minX == control.minX)
        #expect(!result.intersects(fold))
    }

    @Test("Available control areas exclude both the fold and camera")
    func foldAndCamera() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let exclusions = [
            CGRect(x: 480, y: 0, width: 40, height: 800),
            CGRect(x: 900, y: 700, width: 100, height: 100)
        ]
        let control = CGRect(x: 920, y: 740, width: 60, height: 44)
        let offset = ReaderControlLayout.offset(for: control, inside: bounds, avoiding: exclusions)
        let result = control.offsetBy(dx: offset.x, dy: offset.y)

        #expect(bounds.contains(result))
        #expect(exclusions.allSatisfy { !result.intersects($0) })
    }
}
