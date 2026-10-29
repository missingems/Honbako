#if SUMI && DEBUG
import AidokuRunner
import Foundation
import UIKit

/// An explicit owned-image UI fixture. It uses no real pairing, credentials,
/// library mutations, network, or user manga pages.
@MainActor
enum HonbakoPageAccessPreview {
    static var isEnabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--sumi-grid-check") && args.contains("--honbako-page-access-check")
    }

    static func permits(_ manga: AidokuRunner.Manga) -> Bool {
        isEnabled && manga.sourceKey == SumiGridPreviewFixtures.sourceKey
    }

    static func makeService() -> HonbakoPageCoachingService {
        let state = Wire()
        return HonbakoPageCoachingService(transport: { path, method, body in
            try state.request(path: path, method: method, body: body)
        }, connected: { true }, foreground: { UIApplication.shared.applicationState == .active },
        privateReading: { false }, now: Date.init, connectionIdentity: { "owned-page-access-preview" },
        loadImage: { capture in capture.page.sourceId == SumiGridPreviewFixtures.sourceKey ? capture.page.image : nil })
    }

    private final class Wire {
        private var page: HonbakoPageCoachingModels.Publish?
        func request(path: String, method: String, body: Data?) throws -> Data {
            if path.hasSuffix("/revoke") { page = nil; return try json(["ok": true]) }
            if path.hasSuffix("/pause") { return try json(["ok": true]) }
            if method == "POST", let body {
                page = try JSONDecoder().decode(HonbakoPageCoachingModels.Publish.self, from: body)
            }
            guard let page else { return try json(["active": false, "reason": "not_shared", "annotations": [], "annotationRevision": 0]) }
            let annotations: [[String: Any]] = method == "GET" ? [["id": "connected-note", "type": "label",
                "rect": ["x": 0.12, "y": 0.22, "width": 0.76, "height": 0.14],
                "text": "Your connected assistant can annotate this page"]] : []
            return try json(["ok": true, "active": true, "sessionId": page.sessionId,
                "pageId": page.page.pageId, "contentHash": page.page.contentHash,
                "pageGeneration": page.pageGeneration, "expiresAt": NSNull(), "accessMode": "connection",
                "annotationRevision": method == "GET" ? 1 : 0, "annotations": annotations])
        }
        private func json(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    }
}
#endif
