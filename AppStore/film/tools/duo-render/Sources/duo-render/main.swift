// duo-render: draws the iPhone Duo for one film frame at a time.
//
// Reads one JSON request per line on stdin and answers "ok <ms>" (or "error …") on stdout once the
// PNG is written. A request poses the model and frames it with the film's 2D camera:
//
//   {"out": "/path/frame.png", "w": 1920, "h": 1080, "k": 5.83,
//    "cam": {"x": 1300, "y": 548, "zoom": 1, "fx": 0, "fy": 0},
//    "hinge": 180, "yaw": 0, "pitch": 0, "explode": 0,
//    "inner": "/path/inner.jpg", "cover": "/path/cover.jpg" | "asleep"}
//
// Film coordinates: a device point at (px, py) mm from the open device's centre lands at
// x + (px·k − fx)·zoom, y + (py·k − fy)·zoom. `inner` (2853 × 2007) and `cover` (1398 × 2034) are
// optional: a missing key keeps the last texture. The model is Apple's V68.usdz from Xcode.
// `pitch` (degrees) tips the top edge away from the camera, for the film's axonometric plates, and
// `explode` (mm) lifts the inner screen off the body along its normal; both default to 0.
import CoreGraphics
import DuoModel
import Foundation
import ImageIO
import Metal
import RealityKit
import UniformTypeIdentifiers

struct Camera2D: Decodable { var x, y, zoom, fx, fy: Double }
struct Request: Decodable {
  var out: String
  var w: Int
  var h: Int
  var k: Double
  var cam: Camera2D
  var hinge: Double
  var yaw: Double
  var pitch: Double?
  var explode: Double?
  var inner: String?
  var cover: String?
  var ss: Int?
}

let developerDir = ProcessInfo.processInfo.environment["DEVELOPER_DIR"] ?? "/Applications/Xcode 27.1.app/Contents/Developer"
let modelURL = URL(fileURLWithPath: developerDir)
  .deletingLastPathComponent().deletingLastPathComponent()
  .appendingPathComponent("Contents/SharedFrameworks/DeviceKit.framework/Versions/A/PlugIns/CoreDevicePopDeviceKitExtension.devicekitplugin/Contents/Resources/V68.usdz")
let distanceMM = 620.0

func loadCGImage(_ path: String) throws -> CGImage {
  guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
  else { throw NSError(domain: "duo-render", code: 1, userInfo: [NSLocalizedDescriptionKey: "can't read \(path)"]) }
  return image
}

/// A soft studio: warm paper-coloured surroundings, a large softbox overhead and a dimmer fill.
func studioEnvironment() throws -> CGImage {
  let w = 512, h = 256
  var px = [UInt8](repeating: 0, count: w * h * 4)
  for y in 0..<h {
    let lat = (0.5 - (Double(y) + 0.5) / Double(h)) * .pi  // +π/2 straight up
    for x in 0..<w {
      let lon = (Double(x) + 0.5) / Double(w) * 2 * .pi - .pi
      let dir = SIMD3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))
      var c = SIMD3<Double>(0.62, 0.58, 0.52) * (0.55 + 0.45 * max(dir.y, 0))  // warm room
      // Key softbox above and slightly in front of the device, as the camera looks down -Y.
      let key = simd_dot(dir, simd_normalize(SIMD3(-0.35, 1.0, -0.45)))
      if key > 0.93 { c += SIMD3(1.6, 1.55, 1.45) * min(1, (key - 0.93) / 0.02) }
      let fill = simd_dot(dir, simd_normalize(SIMD3(0.8, 0.6, 0.5)))
      if fill > 0.95 { c += SIMD3(0.5, 0.5, 0.5) * min(1, (fill - 0.95) / 0.02) }
      let i = (y * w + x) * 4
      for j in 0..<3 { px[i + j] = UInt8(min(255, pow(min(c[j], 1), 1 / 2.2) * 255)) }
      px[i + 3] = 255
    }
  }
  let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
  return ctx.makeImage()!
}

@MainActor
final class DuoRenderer {
  let device = MTLCreateSystemDefaultDevice()!
  let renderer: RealityRenderer
  let duo: DuoModel
  let stage = Entity()
  let camera = PerspectiveCamera()
  let centre: SIMD3<Float>
  var textures: [DuoModel.Display: String] = [:]
  var targets: [String: MTLTexture] = [:]
  var innerRest: SIMD3<Float>?

  init() async throws {
    renderer = try RealityRenderer()
    renderer.cameraSettings.colorBackground = .color(CGColor(red: 0, green: 0, blue: 0, alpha: 0))
    renderer.lighting.resource = try await EnvironmentResource(equirectangular: try studioEnvironment(), withName: "studio")
    renderer.lighting.intensityExponent = 0.4
    duo = try await DuoModel.load(
      contentsOf: modelURL,
      options: .init(colorVariant: ProcessInfo.processInfo.environment["DUO_FINISH"], innerMapping: .upright)
    )
    duo.setHinge(angleDegrees: 180)
    let bounds = duo.posedBounds()
    centre = bounds.center
    // The stage turns about the open device's centre; the device sits with that centre at the origin.
    duo.root.position = -centre
    stage.addChild(duo.root)
    renderer.entities.append(contentsOf: [stage, camera])
    renderer.activeCamera = camera
    FileHandle.standardError.write("model \(bounds.extents * 1000) mm, centre \(centre * 1000) mm\n".data(using: .utf8)!)
  }

  func setScreen(_ display: DuoModel.Display, _ value: String?) throws {
    guard let value, textures[display] != value else { return }
    textures[display] = value
    if value == "asleep" {
      // Glass with nothing behind it: black, glossy, catching the studio.
      var glass = PhysicallyBasedMaterial()
      glass.baseColor = .init(tint: .black)
      glass.roughness = 0.12
      glass.metallic = 0.0
      glass.clearcoat = 1.0
      duo.setMaterial(glass, for: display)
      return
    }
    let texture = try TextureResource(image: try loadCGImage(value), options: .init(semantic: .color))
    duo.setTexture(texture, for: display)
  }

  func target(_ w: Int, _ h: Int) -> MTLTexture {
    if let t = targets["\(w)x\(h)"] { return t }
    let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb, width: w, height: h, mipmapped: false)
    d.usage = [.renderTarget, .shaderRead]
    d.storageMode = .shared
    let t = device.makeTexture(descriptor: d)!
    targets["\(w)x\(h)"] = t
    return t
  }

  func render(_ r: Request) throws {
    try setScreen(.inner, r.inner)
    try setScreen(.cover, r.cover)
    duo.setHinge(angleDegrees: r.hinge)
    // Model axes: +Y is the inner screen's normal, X runs across the fold, -Z is the top edge.
    let pitch = simd_quatf(angle: Float(-(r.pitch ?? 0) * .pi / 180), axis: [1, 0, 0])
    stage.orientation = pitch * simd_quatf(angle: Float(r.yaw * .pi / 180), axis: [0, 0, 1])
    if let screen = duo.screenEntities[.inner] {
      let rest = innerRest ?? screen.position(relativeTo: duo.root)
      innerRest = rest
      screen.setPosition(rest + [0, Float((r.explode ?? 0) / 1000), 0], relativeTo: duo.root)
    }

    // The film's 2D camera, as a perspective camera looking down -Y with -Z up.
    let k = r.k, zoom = r.cam.zoom
    let ax = (r.cam.fx + (Double(r.w) / 2 - r.cam.x) / zoom) / k
    let az = (r.cam.fy + (Double(r.h) / 2 - r.cam.y) / zoom) / k
    camera.camera.fieldOfViewInDegrees = Float(2 * atan(Double(r.h) / (2 * k * zoom * distanceMM)) * 180 / .pi)
    camera.camera.near = 0.01
    camera.camera.far = 5
    let eye = SIMD3<Float>(Float(ax / 1000), Float(distanceMM / 1000), Float(az / 1000))
    camera.look(at: [eye.x, 0, eye.z], from: eye, upVector: [0, 0, -1], relativeTo: nil)

    let ss = r.ss ?? 2
    let W = r.w * ss, H = r.h * ss
    let texture = target(W, H)
    let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
    // Two passes: the first lets skinning and new materials settle.
    for _ in 0..<2 {
      var done = false
      try renderer.updateAndRender(deltaTime: 1 / 60, cameraOutput: output, onComplete: { _ in done = true })
      while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.0005)) }
    }
    var big = [UInt8](repeating: 0, count: W * H * 4)
    texture.getBytes(&big, bytesPerRow: W * 4, from: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0)
    try writePNG(downsample(big, W, H, ss), r.w, r.h, to: r.out)
  }

  /// Box-filters the supersampled frame and premultiplies for CoreGraphics.
  func downsample(_ src: [UInt8], _ W: Int, _ H: Int, _ s: Int) -> [UInt8] {
    let w = W / s, h = H / s, n = s * s
    var dst = [UInt8](repeating: 0, count: w * h * 4)
    src.withUnsafeBufferPointer { sp in
      dst.withUnsafeMutableBufferPointer { dp in
        for y in 0..<h {
          for x in 0..<w {
            var acc = (0, 0, 0, 0)
            for dy in 0..<s {
              var i = ((y * s + dy) * W + x * s) * 4
              for _ in 0..<s {
                // RealityKit's output is premultiplied; average premultiplied values.
                acc.0 += Int(sp[i]); acc.1 += Int(sp[i + 1]); acc.2 += Int(sp[i + 2]); acc.3 += Int(sp[i + 3])
                i += 4
              }
            }
            let o = (y * w + x) * 4
            dp[o] = UInt8(acc.0 / n); dp[o + 1] = UInt8(acc.1 / n); dp[o + 2] = UInt8(acc.2 / n); dp[o + 3] = UInt8(acc.3 / n)
          }
        }
      }
    }
    return dst
  }

  func writePNG(_ px: [UInt8], _ w: Int, _ h: Int, to path: String) throws {
    var data = px
    let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let image = ctx.makeImage()!
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
      throw NSError(domain: "duo-render", code: 2, userInfo: [NSLocalizedDescriptionKey: "can't write \(path)"])
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
      throw NSError(domain: "duo-render", code: 3, userInfo: [NSLocalizedDescriptionKey: "can't write \(path)"])
    }
  }
}

setvbuf(stdout, nil, _IOLBF, 0)
let finished = DispatchSemaphore(value: 0)
Task { @MainActor in
  do {
    let r = try await DuoRenderer()
    print("ready")
    while let line = readLine() {
      let start = Date()
      do {
        let request = try JSONDecoder().decode(Request.self, from: Data(line.utf8))
        try r.render(request)
        print("ok \(Int(Date().timeIntervalSince(start) * 1000))")
      } catch {
        print("error \(error)")
      }
    }
  } catch {
    print("error \(error)")
  }
  finished.signal()
}
while finished.wait(timeout: .now()) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.002)) }
