@testable import Sumi
import SwiftUI
import UIKit
import Vision
import XCTest

@MainActor
final class HonbakoWidgetDesignTests: XCTestCase {
    func testWidgetDesignsInLightDarkAndLargeText() throws {
        for dark in [false, true] {
            let snapshot = HonbakoWidgetSnapshot.preview
            let view = VStack(alignment: .leading, spacing: 16) {
                Text("Honbako Widgets").font(.largeTitle.bold())
                HStack(spacing: 16) {
                    HonbakoResumeWidgetView(snapshot: snapshot)
                        .padding(8).frame(width: 170, height: 170)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
                    HonbakoReadingTimeWidgetView(snapshot: snapshot, date: snapshot.generatedAt)
                        .padding(16).frame(width: 170, height: 170)
                        .background(Color.blue.opacity(0.1), in: .rect(cornerRadius: 24))
                }
                HonbakoResumeWidgetView(snapshot: snapshot, expanded: true)
                    .padding(16).frame(width: 356, height: 170)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
                HonbakoUpdatesWidgetView(snapshot: snapshot, date: snapshot.generatedAt)
                    .padding(16).frame(width: 356, height: 170)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
                Text("Your library, at a glance.").font(.footnote).foregroundStyle(.secondary)
            }
            .padding(24)
            .background(Color(uiColor: .systemGroupedBackground))
            .environment(\.colorScheme, dark ? .dark : .light)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            let attachment = XCTAttachment(image: image)
            attachment.name = dark ? "widgets-dark" : "widgets-light"
            attachment.lifetime = .keepAlways
            add(attachment)
            let request = VNRecognizeTextRequest()
            try VNImageRequestHandler(cgImage: try XCTUnwrap(image.cgImage)).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").lowercased()
            XCTAssertTrue(text.contains("resume") && text.contains("reading time") && text.contains("new chapters"), text)
        }
        let empty = HonbakoWidgetSnapshot.empty
        let renderer = ImageRenderer(content: HStack {
            HonbakoResumeWidgetView(snapshot: empty).padding(16).frame(width: 170, height: 170)
            HonbakoReadingTimeWidgetView(snapshot: empty, date: .now).padding(16).frame(width: 170, height: 170)
        }.environment(\.dynamicTypeSize, .accessibility1))
        XCTAssertNotNil(renderer.uiImage)
    }
}
