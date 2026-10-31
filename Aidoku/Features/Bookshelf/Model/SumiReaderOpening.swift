#if SUMI
struct SumiReaderOpening {
    let selection: SumiReaderSelection
    let isFirstRead: Bool
    #if HONBAKO_EXTERNAL_SOURCES
    var automaticLanguage: String? = nil
    #endif
}
#endif
