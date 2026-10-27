#if SUMI
import Foundation

enum HonbakoMangaDexError: LocalizedError {
    case invalidIdentifier, invalidResponse, requestFailed(Int), tooManyChapters, unavailableChapter, unavailableLanguage

    var errorDescription: String? {
        switch self {
            case .invalidIdentifier: "This MangaDex title or chapter has an invalid identifier."
            case .invalidResponse: "MangaDex returned an unreadable response."
            case .requestFailed(429): "MangaDex is busy. Please try again later."
            case .requestFailed(401), .requestFailed(403): "MangaDex hasn’t allowed this request. Check the title on its website."
            case .requestFailed: "MangaDex couldn’t be reached. Please try again later."
            case .tooManyChapters: "This title has too many editions to load at once. Choose fewer source languages."
            case .unavailableChapter: "This chapter isn’t available for reading inside Honbako."
            case .unavailableLanguage: "That translation isn’t available for this title on MangaDex."
        }
    }
}
#endif
