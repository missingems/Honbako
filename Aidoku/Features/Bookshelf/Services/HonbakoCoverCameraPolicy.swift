#if SUMI
struct HonbakoCoverCameraPolicy {
    let personalBuild: Bool
    let hingePresent: Bool
    let hingeOpen: Bool
    let readerPresented: Bool
    let coverEnabled: Bool
    let foreground: Bool

    // This is a reader option in both personal and TestFlight builds.
    // Capture still requires the cover toggle, permission and an open reader.
    var usesCameraAccessory: Bool { hingePresent }
    var shouldRunCamera: Bool {
        usesCameraAccessory && hingeOpen && readerPresented && coverEnabled && foreground
    }
}
#endif
