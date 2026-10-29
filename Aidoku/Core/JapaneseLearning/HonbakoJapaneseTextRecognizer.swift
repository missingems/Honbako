import ImageIO
import UIKit
import Vision

@available(iOS 18.0, *)
enum HonbakoJapaneseTextRecognizer {
    enum RecognitionError: Error, LocalizedError {
        case unsupportedImage
        case unsupportedLanguage

        var errorDescription: String? {
            switch self {
                case .unsupportedImage: return "This page could not be opened for text recognition."
                case .unsupportedLanguage: return "Japanese text recognition is unavailable on this device."
            }
        }
    }

    /// Explicit, one-page analysis only. Recognition and transcription never run on the main actor.
    static func recognize(image: UIImage) async throws -> [HonbakoJapaneseRegion] {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            guard let cgImage = image.cgImage else { throw RecognitionError.unsupportedImage }
            let analysisImage = downsample(cgImage)
            var request = RecognizeTextRequest()
            guard request.supportedRecognitionLanguages.contains(where: { $0.languageCode?.identifier == "ja" }) else {
                throw RecognitionError.unsupportedLanguage
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = [Locale.Language(identifier: "ja-JP")]
            request.automaticallyDetectsLanguage = false
            request.usesLanguageCorrection = true
            request.minimumTextHeightFraction = 0.003
            let imageOrientation = orientation(image.imageOrientation)
            let imageSize: CGSize
            switch imageOrientation {
                case .left, .right, .leftMirrored, .rightMirrored:
                    imageSize = CGSize(width: analysisImage.height, height: analysisImage.width)
                default:
                    imageSize = CGSize(width: analysisImage.width, height: analysisImage.height)
            }
            let observations = try await request.perform(on: analysisImage, orientation: imageOrientation)
            try Task.checkCancellation()
            var regions = observations.compactMap { observation -> HonbakoJapaneseRegion? in
                guard let candidate = observation.topCandidates(1).first,
                      HonbakoJapaneseText.containsJapanese(candidate.string),
                      let box = HonbakoJapaneseGeometry.topLeftBox(fromVision: observation.boundingBox.cgRect) else { return nil }
                let text = HonbakoJapaneseText.reading(for: candidate.string)
                let observedDirection: HonbakoJapaneseRegion.Direction
                if #available(iOS 26.0, *) {
                    switch observation.textDirection {
                        case .topToBottom: observedDirection = .vertical
                        case .leftToRight, .rightToLeft: observedDirection = .horizontal
                        case .none: observedDirection = .unknown
                        @unknown default: observedDirection = .unknown
                    }
                } else {
                    observedDirection = .unknown
                }
                let direction = HonbakoJapaneseGeometry.resolvedDirection(
                    observedDirection, for: box, imageSize: imageSize, characterCount: text.text.count)
                return .init(id: 0, text: text.text, reading: text.reading, romaji: text.romaji,
                             confidence: candidate.confidence, readingIsEstimated: text.readingIsEstimated,
                             direction: direction, boundingBox: box,
                             words: wordRegions(for: text, candidate: candidate, parentBox: box, direction: direction))
            }
            let primarilyVertical = regions.filter { $0.direction == .vertical }.count > regions.count / 2
            regions.sort { lhs, rhs in
                if primarilyVertical {
                    if lhs.boundingBox.maxX != rhs.boundingBox.maxX { return lhs.boundingBox.maxX > rhs.boundingBox.maxX }
                    return lhs.boundingBox.minY < rhs.boundingBox.minY
                }
                if lhs.boundingBox.minY != rhs.boundingBox.minY { return lhs.boundingBox.minY < rhs.boundingBox.minY }
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }
            try Task.checkCancellation()
            return regions.enumerated().map { index, region in
                HonbakoJapaneseRegion(
                    id: index + 1, text: region.text, reading: region.reading, romaji: region.romaji,
                    confidence: region.confidence, readingIsEstimated: region.readingIsEstimated,
                    direction: region.direction, boundingBox: region.boundingBox, words: region.words
                )
            }
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    /// Word ranges use the recognizer's own character geometry. Some Vision
    /// revisions return a whole line for every range; those boxes are ambiguous.
    private static func wordRegions(
        for reading: HonbakoJapaneseReading,
        candidate: RecognizedText,
        parentBox: CGRect,
        direction: HonbakoJapaneseRegion.Direction
    ) -> [HonbakoJapaneseWordRegion] {
        let original = candidate.string
        let offset = original.range(of: reading.text).map { NSRange($0, in: original).location }
        let anchored = reading.words.map { word -> HonbakoJapaneseWordRegion in
            guard let offset,
                  let range = Range(NSRange(location: offset + word.range.location, length: word.range.length), in: original),
                  let rectangle = candidate.boundingBox(for: range),
                  let box = HonbakoJapaneseGeometry.topLeftBox(fromVision: rectangle.boundingBox.cgRect) else {
                return .init(word: word, boundingBox: nil)
            }
            return .init(word: word, boundingBox: box)
        }
        let validated = HonbakoJapaneseWordGeometry.validated(anchored, in: parentBox)
        guard direction == .vertical, validated.contains(where: { $0.boundingBox == nil }) else { return validated }
        let recovered = validated.map { item -> HonbakoJapaneseWordRegion in
            guard item.boundingBox == nil, let offset,
                  let range = Range(NSRange(location: offset + item.word.range.location, length: item.word.range.length), in: original) else { return item }
            var characterBoxes: [CGRect] = []
            var index = range.lowerBound
            while index < range.upperBound {
                let next = original.index(after: index)
                guard next <= range.upperBound,
                      let rectangle = candidate.boundingBox(for: index..<next),
                      let box = HonbakoJapaneseGeometry.topLeftBox(fromVision: rectangle.boundingBox.cgRect) else { return item }
                characterBoxes.append(box)
                index = next
            }
            return .init(word: item.word,
                         boundingBox: HonbakoJapaneseWordGeometry.characterUnion(characterBoxes, in: parentBox))
        }
        return HonbakoJapaneseWordGeometry.validated(recovered, in: parentBox)
    }

    private static func downsample(_ image: CGImage) -> CGImage {
        let maximumDimension = 4096
        let scale = min(1, Double(maximumDimension) / Double(max(image.width, image.height)))
        guard scale < 1,
              let context = CGContext(
                data: nil, width: max(1, Int(Double(image.width) * scale)), height: max(1, Int(Double(image.height) * scale)),
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        return context.makeImage() ?? image
    }

    private static func orientation(_ orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
            case .up: return .up
            case .down: return .down
            case .left: return .left
            case .right: return .right
            case .upMirrored: return .upMirrored
            case .downMirrored: return .downMirrored
            case .leftMirrored: return .leftMirrored
            case .rightMirrored: return .rightMirrored
            @unknown default: return .up
        }
    }
}
