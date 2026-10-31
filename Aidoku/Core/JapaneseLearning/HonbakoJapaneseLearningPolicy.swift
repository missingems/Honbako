#if SUMI
/// Pro grants access to the guide, never permission to annotate Chinese or
/// unknown-language pages or to turn the reader's setting on automatically.
struct HonbakoJapaneseLearningPolicy {
    let requested: Bool
    let languageEligible: Bool
    let hasPro: Bool

    var enabled: Bool { requested && languageEligible && hasPro }
}
#endif
