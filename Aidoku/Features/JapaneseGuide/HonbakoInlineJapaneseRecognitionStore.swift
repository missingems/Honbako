#if SUMI
import UIKit

/// One OCR lane for the live reader. Completed entries never retain page bitmaps.
actor HonbakoInlineJapaneseRecognitionStore {
    typealias Recognizer = @Sendable (UIImage) async throws -> [HonbakoJapaneseRegion]
    static let shared = HonbakoInlineJapaneseRecognitionStore()

    private final class Entry {
        weak var image: UIImage?
        let regions: [HonbakoJapaneseRegion]
        var access: UInt64

        init(image: UIImage, regions: [HonbakoJapaneseRegion], access: UInt64) {
            self.image = image
            self.regions = regions
            self.access = access
        }
    }

    private struct Flight {
        let id: UUID
        let image: UIImage
        let task: Task<[HonbakoJapaneseRegion], Error>
        var clients: Set<UUID>
    }

    private let capacity: Int
    private let recognizer: Recognizer
    private let lane = HonbakoInlineJapaneseRecognitionLane()
    private var cache: [ObjectIdentifier: Entry] = [:]
    private var flights: [ObjectIdentifier: Flight] = [:]
    private var clock: UInt64 = 0

    init(capacity: Int = 8, recognizer: @escaping Recognizer = { image in
        try await HonbakoJapaneseTextRecognizer.recognize(image: image)
    }) {
        self.capacity = max(0, min(capacity, 16))
        self.recognizer = recognizer
    }

    func regions(for image: UIImage) async throws -> [HonbakoJapaneseRegion] {
        try Task.checkCancellation()
        prune()
        let key = ObjectIdentifier(image)
        clock &+= 1
        if let entry = cache[key], entry.image === image {
            entry.access = clock
            return entry.regions
        }
        let client = UUID()
        let flight: Flight
        if var existing = flights[key], existing.image === image {
            existing.clients.insert(client)
            flights[key] = existing
            flight = existing
        } else {
            let recognize = recognizer
            let lane = lane
            let task = Task {
                try await lane.run { try await recognize(image) }
            }
            flight = Flight(id: UUID(), image: image, task: task, clients: [client])
            flights[key] = flight
        }
        return try await withTaskCancellationHandler {
            do {
                let regions = try await flight.task.value
                try Task.checkCancellation()
                complete(key: key, flightID: flight.id, image: image, regions: regions)
                return regions
            } catch {
                release(key: key, flightID: flight.id, client: client)
                throw error
            }
        } onCancel: {
            Task { await self.release(key: key, flightID: flight.id, client: client) }
        }
    }

    private func complete(key: ObjectIdentifier, flightID: UUID, image: UIImage, regions: [HonbakoJapaneseRegion]) {
        guard flights[key]?.id == flightID else { return }
        flights.removeValue(forKey: key)
        // OCR metadata has a bound as well as the bitmap-free entry count.
        guard capacity > 0, regions.count <= 256,
              regions.reduce(0, { $0 + $1.words.count }) <= 2_048,
              regions.reduce(0, { $0 + $1.text.utf16.count }) <= 24_000 else { return }
        cache[key] = Entry(image: image, regions: regions, access: clock)
        prune()
    }

    private func release(key: ObjectIdentifier, flightID: UUID, client: UUID) {
        guard var flight = flights[key], flight.id == flightID else { return }
        flight.clients.remove(client)
        if flight.clients.isEmpty {
            flights.removeValue(forKey: key)
            flight.task.cancel()
        } else {
            flights[key] = flight
        }
    }

    private func prune() {
        cache = cache.filter { $0.value.image != nil }
        while cache.count > capacity, let oldest = cache.min(by: { $0.value.access < $1.value.access })?.key {
            cache.removeValue(forKey: oldest)
        }
    }

    func diagnostics() -> (cachedEntries: Int, inFlight: Int, activeClients: Int) {
        prune()
        return (cache.count, flights.count, flights.values.reduce(0) { $0 + $1.clients.count })
    }
}

/// Cancellation removes a queued job immediately instead of retaining its image
/// until all other pages finish. A cancelled job that acquired the lane releases it.
private actor HonbakoInlineJapaneseRecognitionLane {
    private var busy = false
    private var waiters: [(UUID, CheckedContinuation<Void, Error>)] = []

    func run(_ operation: @Sendable () async throws -> [HonbakoJapaneseRegion]) async throws -> [HonbakoJapaneseRegion] {
        try await acquire()
        defer { release() }
        try Task.checkCancellation()
        return try await operation()
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        if !busy {
            busy = true
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append((id, continuation))
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func cancel(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.0 == id }) else { return }
        waiters.remove(at: index).1.resume(throwing: CancellationError())
    }

    private func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().1.resume()
        }
    }
}
#endif
