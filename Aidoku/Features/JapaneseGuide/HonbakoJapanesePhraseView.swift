#if SUMI
import SwiftUI
import Translation

@available(iOS 18.0, *)
@MainActor
struct HonbakoJapanesePhraseView: View {
    let confidence: Float?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var isEditingText: Bool
    @State private var text: String
    @State private var reading: HonbakoJapaneseReading
    @State private var selectedWordID: Int?
    @State private var speech = HonbakoJapaneseSpeech()
    @State private var configuration: TranslationSession.Configuration?
    @State private var translation: String?
    @State private var translationError: String?
    @State private var isTranslating = false
    @State private var requestID = UUID()

    init(text: String, confidence: Float?, initialWordID: Int? = nil) {
        self.confidence = confidence
        _text = State(initialValue: text)
        _reading = State(initialValue: HonbakoJapaneseText.reading(for: text))
        _selectedWordID = State(initialValue: initialWordID)
    }

    var body: some View {
        #if targetEnvironment(simulator)
        content
        #else
        content.translationTask(configuration) { session in
            await translate(using: session)
        }
        #endif
    }

    private var content: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Enter Japanese text", text: $text, axis: .vertical)
                        .lineLimit(2...8)
                        .font(.title3)
                        .focused($isEditingText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("Honbako.JapaneseGuide.CorrectText")
                } header: {
                    Text("Japanese")
                } footer: {
                    Text("Correct any missed characters before listening or translating.")
                }
                if !reading.text.isEmpty {
                    readings
                    pronunciation
                    translationSection
                }
            }
            .accessibilityIdentifier("Honbako.JapaneseGuide.PhraseForm")
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Read This Phrase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isEditingText = false }
                        .accessibilityIdentifier("Honbako.JapaneseGuide.KeyboardDone")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("Honbako.JapaneseGuide.PhraseDone")
                }
            }
            .onChange(of: text) { _, value in
                speech.stop()
                requestID = UUID()
                configuration = nil
                translation = nil
                translationError = nil
                isTranslating = false
                if value.count > 2_000 { text = String(value.prefix(2_000)) }
                selectedWordID = nil
                reading = HonbakoJapaneseText.reading(for: text)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { speech.stop() }
            }
            .onDisappear {
                speech.stop()
                requestID = UUID()
                configuration = nil
            }
        }
        .tint(.primary)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("Honbako.JapaneseGuide.Phrase")
    }

    private var selectedWord: HonbakoJapaneseWord? {
        reading.words.first { $0.id == selectedWordID }
    }

    private var activeText: String { selectedWord?.text ?? reading.text }

    private var readings: some View {
        Section {
            if !reading.words.isEmpty {
                Button("Whole Phrase", systemImage: "text.bubble") { selectWord(nil) }
                    .accessibilityIdentifier("Honbako.JapaneseGuide.WholePhrase")
                    .accessibilityAddTraits(selectedWordID == nil ? .isSelected : [])
                HonbakoJapaneseWordFlow {
                    ForEach(reading.words) { word in
                        Button { selectWord(word.id) } label: {
                            HonbakoJapaneseWordLabel(word: word, selected: selectedWordID == word.id)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(HonbakoJapaneseWordLabel.accessibilityText(for: word)))
                        .accessibilityAddTraits(selectedWordID == word.id ? .isSelected : [])
                        .accessibilityHint("Hear or translate this word")
                        .accessibilityIdentifier("Honbako.JapaneseGuide.Reading.Word.\(word.id)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
            } else {
                Text("A reading isn’t available for this text. You can still listen to the Japanese or try a shorter phrase.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Japanese Reading")
        } footer: {
            Text("Tap a word to hear or translate it. Choose Whole Phrase for the full sentence.")
            if reading.readingIsEstimated {
                Text("This is a suggested reading. Names, unusual spellings, and words with several readings may sound different in context.")
            }
            if let confidence, confidence < 0.65 {
                Text("Text recognition is uncertain. Check the Japanese against the page.")
            }
        }
    }

    private var pronunciation: some View {
        Section {
            if let selectedWord {
                LabeledContent("Selected Word", value: selectedWord.text)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("Honbako.JapaneseGuide.SelectedWord")
            }
            Button("Listen", systemImage: "speaker.wave.2") {
                isEditingText = false
                speech.speak(activeText)
            }
                .disabled(!speech.isAvailable)
                .accessibilityValue(Text(activeText))
                .accessibilityIdentifier("Honbako.JapaneseGuide.Speak")
            Button("Listen Slowly", systemImage: "tortoise") {
                isEditingText = false
                speech.speak(activeText, slowly: true)
            }
                .disabled(!speech.isAvailable)
                .accessibilityValue(Text(activeText))
                .accessibilityIdentifier("Honbako.JapaneseGuide.SpeakSlowly")
            Button("Stop Audio", systemImage: "stop.circle") { speech.stop() }
                .disabled(!speech.isAvailable)
                .accessibilityIdentifier("Honbako.JapaneseGuide.StopSpeech")
        } header: {
            Text("Pronunciation")
        } footer: {
            if !speech.isAvailable {
                Text("A Japanese system voice isn’t available. Add a Japanese voice in iPhone Settings to hear this phrase.")
            }
        }
    }

    private var translationSection: some View {
        Section {
            if let translation {
                Text(translation).textSelection(.enabled)
                    .accessibilityIdentifier("Honbako.JapaneseGuide.Translation")
            }
            if isTranslating {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Translating…")
                }
                .accessibilityIdentifier("Honbako.JapaneseGuide.Translating")
            }
            if let translationError {
                Text(translationError).font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("Honbako.JapaneseGuide.TranslationError")
            }
            #if targetEnvironment(simulator)
            Text("Translation is available on iPhone and iPad. Apple’s translation service doesn’t run in Simulator.")
                .font(.subheadline).foregroundStyle(.secondary)
                .accessibilityIdentifier("Honbako.JapaneseGuide.TranslationUnavailable")
            #else
            Button(translation == nil ? String(localized: "Translate to English") : String(localized: "Translate Again"),
                   systemImage: "translate") {
                requestTranslation()
            }
            .disabled(isTranslating)
            .accessibilityValue(Text(activeText))
            .accessibilityIdentifier("Honbako.JapaneseGuide.Translate")
            #endif
        } header: {
            Text("Meaning")
        } footer: {
            Text("""
            Translate when you’re ready to check your understanding. Apple may ask to download Japanese and English language support. \
            Short phrases can lose context.
            """)
        }
    }

    private func selectWord(_ identifier: Int?) {
        guard selectedWordID != identifier else { return }
        isEditingText = false
        speech.stop()
        selectedWordID = identifier
        requestID = UUID()
        configuration = nil
        translation = nil
        translationError = nil
        isTranslating = false
    }

    private func requestTranslation() {
        isEditingText = false
        speech.stop()
        requestID = UUID()
        translationError = nil
        isTranslating = true
        if configuration == nil {
            configuration = .init(source: .init(identifier: "ja"), target: .init(identifier: "en"))
        } else {
            configuration?.invalidate()
        }
    }

    private func translate(using session: TranslationSession) async {
        let source = activeText
        let identity = requestID
        guard !source.isEmpty, configuration != nil else { return }
        defer { if requestID == identity { isTranslating = false } }
        do {
            let response = try await session.translate(source)
            guard !Task.isCancelled, requestID == identity, activeText == source else { return }
            translation = response.targetText
            translationError = nil
            isTranslating = false
        } catch {
            guard !Task.isCancelled, requestID == identity else { return }
            isTranslating = false
            translationError = String(localized: """
            Translation couldn’t finish. Check language downloads and try again. \
            You can keep using the reading and pronunciation tools.
            """)
        }
    }
}
#endif
