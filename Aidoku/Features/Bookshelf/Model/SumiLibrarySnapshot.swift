#if SUMI
/// Saved and recent books from one completed library read.
struct SumiLibrarySnapshot: Sendable {
    let saved: [SumiBook]
    let recent: [SumiBook]
}
#endif
