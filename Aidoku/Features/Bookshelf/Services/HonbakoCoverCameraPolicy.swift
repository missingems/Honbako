#if SUMI
struct HonbakoCoverCameraPolicy {
    let personalBuild: Bool
    let hingePresent: Bool
    let hingeOpen: Bool
    let readerPresented: Bool
    let coverEnabled: Bool
    let foreground: Bool

    var usesCameraAccessory: Bool { personalBuild && hingePresent }
    var shouldRunCamera: Bool {
        usesCameraAccessory && hingeOpen && readerPresented && coverEnabled && foreground
    }
}
#endif
