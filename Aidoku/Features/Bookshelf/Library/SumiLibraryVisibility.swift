#if SUMI
import Combine

/// Owned by the library's native navigation controller so an over-full-screen
/// detail can suspend the tabletop without relying on view disappearance.
@MainActor
final class SumiLibraryVisibility: ObservableObject {
    @Published var isObscured = false
}
#endif
