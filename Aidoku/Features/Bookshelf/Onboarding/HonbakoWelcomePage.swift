#if SUMI
import SwiftUI

enum HonbakoWelcomePage: Int, CaseIterable, Identifiable, Hashable {
    case library, assistant, plans
    var id: Int { rawValue }

    var navigationTitle: LocalizedStringKey {
        switch self {
        case .library: "Honbako"
        case .assistant: "Your AI"
        case .plans: "Plans"
        }
    }

    var symbol: String {
        switch self {
        case .library: "books.vertical"
        case .assistant: "bubble.left.and.bubble.right"
        case .plans: "star.circle"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .library: "Read your own manga"
        case .assistant: "Your AI reading companion"
        case .plans: "Choose your plan"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .library: "Bring your own manga from Files, your personal server, or the sources you choose."
        case .assistant: "Connect your own AI provider through MCP. Let your companion explore your library and help with the page in front of you."
        case .plans: "Read for free. Connect from anywhere with Pro."
        }
    }

    var next: Self? {
        switch self {
        case .library: .assistant
        case .assistant: .plans
        case .plans: nil
        }
    }

    var navigationPath: [Self] {
        switch self {
        case .library: []
        case .assistant: [.assistant]
        case .plans: [.assistant, .plans]
        }
    }
}
#endif
