#if SUMI
import Combine

@MainActor
final class SumiGridOpeningState: ObservableObject {
    @Published var bookID: String?
}
#endif
