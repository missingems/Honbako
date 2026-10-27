#if SUMI
import AidokuRunner
import Combine
import Foundation
import UIKit

/// The reader and its optional accessory share this model. The system owns
/// presentation; this model never selects or activates a physical display.
@MainActor
final class HonbakoCoverDisplayModel: ObservableObject {
    struct Status: Codable, Equatable {
        var accessoryKind = "externalNonInteractive"
        var registered = false
        var available = false
        var enabled = false
        var sceneConnected = false
        var imageState = "notRequested"
        var cameraState = "notRequested"
        var hingePresent = false
        var hingeOpen = false
        var title = ""
        var sceneRole: String?
        var displayWidth: Double?
        var displayHeight: Double?
        var event = "initialized"
        var updatedAt = Date.now
    }

    @Published private(set) var image: UIImage?
    @Published private(set) var title = ""
    private(set) var status = Status()
    private var bookID: MangaIdentifier?
    private var imageTask: Task<Void, Never>?
    private let writesDiagnostics: Bool

    init(writesDiagnostics: Bool = HonbakoProStore.personalFeaturesEnabled) {
        self.writesDiagnostics = writesDiagnostics
    }

    func prepare(manga: AidokuRunner.Manga, source: AidokuRunner.Source?) {
        guard bookID != manga.identifier else { return }
        imageTask?.cancel()
        bookID = manga.identifier
        title = manga.title
        status.title = manga.title
        let book = SumiBook(manga: manga)
        image = SumiCoverArtworkLoader.shared.cachedCover(for: book)
        status.imageState = image == nil ? "loading" : "ready"
        record("coverRequested")
        guard image == nil else { return }
        imageTask = Task { [weak self] in
            let loaded = await SumiCoverArtworkLoader.shared.loadCover(for: book, source: source)
            guard !Task.isCancelled, let self, bookID == manga.identifier else { return }
            image = loaded
            status.imageState = loaded == nil ? "unavailable" : "ready"
            record("coverResolved")
        }
    }

    func setRegistration(_ registered: Bool, enabled: Bool) {
        status.registered = registered
        status.enabled = enabled
        if !registered {
            imageTask?.cancel()
            imageTask = nil
            status.available = false
            status.sceneConnected = false
        }
        record(registered ? "registered" : "unregistered")
    }

    func setAvailability(_ available: Bool, enabled: Bool) {
        guard status.available != available || status.enabled != enabled else { return }
        status.available = available
        status.enabled = enabled
        record("availabilityChanged")
    }

    func setAccessoryKind(_ kind: String) {
        guard status.accessoryKind != kind else { return }
        status.accessoryKind = kind
        record("accessoryKindChanged")
    }

    func setCameraState(_ state: String) {
        guard status.cameraState != state else { return }
        status.cameraState = state
        record("cameraStateChanged")
    }

    func setHinge(present: Bool, open: Bool) {
        guard status.hingePresent != present || status.hingeOpen != open else { return }
        status.hingePresent = present
        status.hingeOpen = open
        record("hingeChanged")
    }

    func setSceneConnected(_ connected: Bool, role: String, size: CGSize? = nil) {
        status.sceneConnected = connected
        status.sceneRole = role
        if let size {
            status.displayWidth = Double(size.width)
            status.displayHeight = Double(size.height)
        }
        record(connected ? "sceneConnected" : "sceneDisconnected")
    }

    func recordUnsupportedSystem() {
        record("requiresIOS27")
    }

    private func record(_ event: String) {
        status.event = event
        status.updatedAt = .now
        // Diagnostic evidence for the owner's installation only. Nothing is
        // uploaded, and ordinary App Store installations do not write this file.
        guard writesDiagnostics else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(status) else { return }
        let url = URL.documentsDirectory.appending(path: "HonbakoCoverDisplayStatus.json")
        try? data.write(to: url, options: .atomic)
    }

    deinit { imageTask?.cancel() }
}
#endif
