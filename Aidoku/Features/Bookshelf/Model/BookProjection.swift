#if SUMI
import Foundation
import SwiftUI

/// Projects each physical face independently, so SwiftUI does not flatten a
/// stack of rotated rectangles into a single card before rotating the book.
struct BookProjection {
    struct Point {
        var x: CGFloat
        var y: CGFloat
        var z: CGFloat
    }

    struct Face {
        let origin: Point
        let horizontal: Point
        let vertical: Point
        let size: CGSize
        let normal: Point
    }

    let center: CGPoint
    let focalLength: CGFloat
    let yaw: Double
    let pitch: Double

    func transform(for face: Face) -> ProjectionTransform {
        let origin = rotated(face.origin)
        let horizontal = rotated(face.horizontal)
        let vertical = rotated(face.vertical)
        let denominatorX = -horizontal.z / focalLength
        let denominatorY = -vertical.z / focalLength
        let denominatorOffset = 1 - origin.z / focalLength
        var result = ProjectionTransform()
        result.m11 = horizontal.x + center.x * denominatorX
        result.m21 = vertical.x + center.x * denominatorY
        result.m31 = origin.x + center.x * denominatorOffset
        result.m12 = horizontal.y + center.y * denominatorX
        result.m22 = vertical.y + center.y * denominatorY
        result.m32 = origin.y + center.y * denominatorOffset
        result.m13 = denominatorX
        result.m23 = denominatorY
        result.m33 = denominatorOffset
        return result
    }

    func isFacingViewer(_ face: Face) -> Bool {
        rotated(face.normal).z > 0.001
    }

    func depth(of face: Face) -> Double {
        let midpoint = Point(
            x: face.origin.x + face.horizontal.x * face.size.width / 2 + face.vertical.x * face.size.height / 2,
            y: face.origin.y + face.horizontal.y * face.size.width / 2 + face.vertical.y * face.size.height / 2,
            z: face.origin.z + face.horizontal.z * face.size.width / 2 + face.vertical.z * face.size.height / 2
        )
        return Double(rotated(midpoint).z)
    }

    private func rotated(_ point: Point) -> Point {
        let cosineY = CGFloat(cos(yaw * .pi / 180))
        let sineY = CGFloat(sin(yaw * .pi / 180))
        let cosineX = CGFloat(cos(pitch * .pi / 180))
        let sineX = CGFloat(sin(pitch * .pi / 180))
        let x = cosineY * point.x + sineY * point.z
        let z = -sineY * point.x + cosineY * point.z
        return Point(x: x, y: cosineX * point.y - sineX * z,
                     z: sineX * point.y + cosineX * z)
    }
}
#endif
