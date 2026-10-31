// swift-tools-version: 6.0
// Renders Apple's iPhone Duo model (V68.usdz, shipped inside Xcode 27.1's DeviceHub plugin) for the
// film: one device layer per frame, posed and lit, with the genuine captures on its screens.
import PackageDescription

let package = Package(
  name: "duo-render",
  platforms: [.macOS("27.0")],
  targets: [
    // Copied unchanged from SpatialSim's Client/DeviceModel/Sources (commit bfc9945), which
    // measured and rigged the model.
    .target(name: "DuoModel", path: "Sources/DuoModel"),
    .executableTarget(
      name: "duo-render",
      dependencies: ["DuoModel"],
      path: "Sources/duo-render",
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
  ]
)
