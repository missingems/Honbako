#if SUMI
/// This capability is fixed at compilation, independently of Pro entitlement.
enum HonbakoSourceScope {
    #if HONBAKO_EXTERNAL_SOURCES
    static let externalSourcesEnabled = true
    #else
    static let externalSourcesEnabled = false
    #endif
}
#endif
