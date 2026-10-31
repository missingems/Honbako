#if SUMI
struct HonbakoCoverCameraPolicy {
    let personalBuild: Bool
    var verifiedPro = false
    let hingePresent: Bool
    let hingeOpen: Bool
    let readerPresented: Bool
    let coverEnabled: Bool
    let foreground: Bool

    // Personal builds retain their signed-build access. Public builds need
    // current verified Pro, plus the independent cover/camera intent gates.
    var hasAccess: Bool { personalBuild || verifiedPro }
    var usesCameraAccessory: Bool { hingePresent }
    var shouldEnableAccessory: Bool {
        hasAccess && readerPresented && coverEnabled && foreground && (!usesCameraAccessory || hingeOpen)
    }
    var shouldRunCamera: Bool { usesCameraAccessory && shouldEnableAccessory }
}
#endif
