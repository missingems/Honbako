#if SUMI
import SwiftUI

/// Six projected surfaces form a real volume. Animation interpolates two
/// angles through SwiftUI; there is no display link or permanent animation.
struct PhysicalBookMesh: View, Animatable {
    let book: BookPresentation
    let canvasSize: CGSize
    let bookSize: CGSize
    let thickness: CGFloat
    let center: CGPoint
    var yaw: Double
    var pitch: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(yaw, pitch) }
        set { yaw = newValue.first; pitch = newValue.second }
    }

    private var projection: BookProjection {
        BookProjection(center: center, focalLength: max(500, bookSize.height * 3.5), yaw: yaw, pitch: pitch)
    }

    var body: some View {
        let halfWidth = bookSize.width / 2
        let halfHeight = bookSize.height / 2
        let halfDepth = thickness / 2
        let front = BookProjection.Face(origin: .init(x: -halfWidth, y: -halfHeight, z: halfDepth), horizontal: .init(x: 1, y: 0, z: 0), vertical: .init(x: 0, y: 1, z: 0), size: bookSize, normal: .init(x: 0, y: 0, z: 1))
        let back = BookProjection.Face(origin: .init(x: halfWidth, y: -halfHeight, z: -halfDepth), horizontal: .init(x: -1, y: 0, z: 0), vertical: .init(x: 0, y: 1, z: 0), size: bookSize, normal: .init(x: 0, y: 0, z: -1))
        let spine = BookProjection.Face(origin: .init(x: -halfWidth, y: -halfHeight, z: -halfDepth), horizontal: .init(x: 0, y: 0, z: 1), vertical: .init(x: 0, y: 1, z: 0), size: CGSize(width: thickness, height: bookSize.height), normal: .init(x: -1, y: 0, z: 0))
        let foreEdge = BookProjection.Face(origin: .init(x: halfWidth - 0.8, y: -halfHeight, z: halfDepth), horizontal: .init(x: 0, y: 0, z: -1), vertical: .init(x: 0, y: 1, z: 0), size: CGSize(width: thickness, height: bookSize.height), normal: .init(x: 1, y: 0, z: 0))
        let top = BookProjection.Face(origin: .init(x: -halfWidth, y: -halfHeight + 0.7, z: -halfDepth), horizontal: .init(x: 1, y: 0, z: 0), vertical: .init(x: 0, y: 0, z: 1), size: CGSize(width: bookSize.width, height: thickness), normal: .init(x: 0, y: -1, z: 0))
        let bottom = BookProjection.Face(origin: .init(x: -halfWidth, y: halfHeight - 0.7, z: halfDepth), horizontal: .init(x: 1, y: 0, z: 0), vertical: .init(x: 0, y: 0, z: -1), size: CGSize(width: bookSize.width, height: thickness), normal: .init(x: 0, y: 1, z: 0))
        ZStack(alignment: .topLeading) {
            face(BookCoverFace(book: book), on: front)
            face(BookCoverFace(book: book, isBack: true), on: back)
            face(BookSpineFace(book: book), on: spine)
            face(paper(horizontalLines: false), on: foreEdge)
            face(paper(horizontalLines: true), on: top)
            face(paper(horizontalLines: true), on: bottom)
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func face<Content: View>(_ content: Content, on face: BookProjection.Face) -> some View {
        content
            .frame(width: face.size.width, height: face.size.height)
            .projectionEffect(projection.transform(for: face))
            .opacity(projection.isFacingViewer(face) ? 1 : 0)
            .zIndex(projection.depth(of: face))
    }

    private func paper(horizontalLines: Bool) -> some View {
        BookPaperFace(horizontalLines: horizontalLines)
            .padding(horizontalLines ? .horizontal : .vertical, 2)
            .padding(horizontalLines ? .vertical : .horizontal, 1.3)
            .background(book.accentColor.opacity(0.65))
    }
}
#endif
