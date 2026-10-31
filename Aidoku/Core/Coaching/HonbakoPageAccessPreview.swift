#if SUMI && DEBUG
import AidokuRunner
import Foundation
import UIKit

/// An explicit sample-image UI fixture. It uses no real pairing, credentials,
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
            var annotations: [[String: Any]] = method == "GET" ? [["id": "connected-note", "type": "label",
                "rect": ["x": 0.12, "y": 0.22, "width": 0.76, "height": 0.14],
                "text": "Your connected assistant can annotate this page"]] : []
            if method == "GET", SumiGridPreviewFixtures.usesOwnedMarketingSample {
                let language = HonbakoTutorialManga.language(for: Locale.preferredLanguages.first ?? "en")
                let note = ["en": "Nori is Mina’s cat.", "ja": "ノリはミナの飼い猫です。", "zh-Hans": "诺里是米娜的猫。", "zh-Hant": "諾里是米娜的貓。"] [language]!
                annotations = [
                    ["id": "sample-cat", "type": "box", "color": "yellow",
                     "rect": ["x": 0.58, "y": 0.025, "width": 0.36, "height": 0.18]],
                    ["id": "sample-arrow", "type": "arrow", "color": "yellow",
                     "from": ["x": 0.44, "y": 0.27], "to": ["x": 0.70, "y": 0.13]],
                    ["id": "sample-note", "type": "label", "color": "yellow",
                     "rect": ["x": 0.12, "y": 0.22, "width": 0.40, "height": 0.065], "text": note]
                ]
            }
            if method == "GET", SumiGridPreviewFixtures.usesLicensedMarketingSample {
                let language = HonbakoTutorialManga.language(for: Locale.preferredLanguages.first ?? "en")
                let note = ["en": "Akari is waiting for the last train.", "ja": "アカリは終電を待っています。", "zh-Hans": "小光正在等待末班车。", "zh-Hant": "小光正在等待末班車。"] [language]!
                annotations = [
                    ["id": "sample-character", "type": "box", "color": "yellow",
                     "rect": ["x": 0.20, "y": 0.62, "width": 0.50, "height": 0.33]],
                    ["id": "sample-arrow", "type": "arrow", "color": "yellow",
                     "from": ["x": 0.52, "y": 0.58], "to": ["x": 0.43, "y": 0.72]],
                    ["id": "sample-note", "type": "label", "color": "yellow",
                     "rect": ["x": 0.13, "y": 0.53, "width": 0.72, "height": 0.065], "text": note]
                ]
            }
            return try json(["ok": true, "active": true, "sessionId": page.sessionId,
                "pageId": page.page.pageId, "contentHash": page.page.contentHash,
                "pageGeneration": page.pageGeneration, "expiresAt": NSNull(), "accessMode": "connection",
                "annotationRevision": method == "GET" ? 1 : 0, "annotations": annotations])
        }
        private func json(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    }
}
#endif
