import AVFoundation

@MainActor
final class HonbakoJapaneseSpeech {
    private let synthesizer = AVSpeechSynthesizer()

    var isAvailable: Bool {
        AVSpeechSynthesisVoice(language: "ja-JP") != nil
    }

    func speak(_ text: String, slowly: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let voice = AVSpeechSynthesisVoice(language: "ja-JP") else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = voice
        utterance.rate = slowly ? AVSpeechUtteranceDefaultSpeechRate * 0.7 : AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
