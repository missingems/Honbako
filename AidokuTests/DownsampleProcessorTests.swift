//
//  DownsampleProcessorTests.swift
//  AidokuTests
//

@testable import Aidoku
import Testing
import UIKit

@MainActor
struct DownsampleProcessorTests {
    @Test("Processed image cache distinguishes display widths and scales")
    func displayGeometryCacheKeys() {
        let outer = DownsampleProcessor(width: 400, scaleFactor: 2)
        let inner = DownsampleProcessor(width: 800, scaleFactor: 2)
        let denserDisplay = DownsampleProcessor(width: 400, scaleFactor: 3)

        #expect(outer.identifier != inner.identifier)
        #expect(outer.identifier != denserDisplay.identifier)
    }

    @Test("A wider reader requests a larger image from the original pixels")
    func largerImageForWiderReader() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let original = UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 3000), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2000, height: 3000))
        }
        let outer = try #require(DownsampleProcessor(width: 400, scaleFactor: 2).process(original))
        let inner = try #require(DownsampleProcessor(width: 800, scaleFactor: 2).process(original))

        #expect(try #require(outer.cgImage).width == 800)
        #expect(try #require(inner.cgImage).width == 1600)
    }
}
