#if SUMI
/// Initial loading is independent of background refreshes and search operations.
/// Only a successfully published snapshot can establish an empty library.
enum SumiLibraryLoadState: Equatable {
    case loading
    case loaded
    case failed(String)
}
#endif
