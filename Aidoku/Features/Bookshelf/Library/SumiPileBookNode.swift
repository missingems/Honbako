#if SUMI
import Nuke
import SceneKit
import SwiftUI
import UIKit

/// Cover boards, a striped paper block and a bound spine are separate
/// pieces of geometry. The physics hull is the closed book.
final class SumiPileBookNode: SCNNode {
    private(set) var book: SumiBook
    var hasRenderedPresentation = false
    private let frontMaterial = SCNMaterial()
    private var coverTask: Task<Void, Never>?
    private var loadedURL: URL?
    private var hasCoverImage = false

    var bookID: String { book.presentation.id }

    init(book: SumiBook) {
        self.book = book
        super.init()
        name = book.presentation.id
        buildGeometry()
        update(book: book)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(book: SumiBook) {
        self.book = book
        if !hasCoverImage { frontMaterial.diffuse.contents = coverTexture(image: nil) }
        guard book.coverURL != loadedURL else { return }
        loadedURL = book.coverURL
        hasCoverImage = false
        frontMaterial.diffuse.contents = coverTexture(image: nil)
        coverTask?.cancel()
        guard let url = book.coverURL else { return }
        coverTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let source = await SourceManager.shared.source(for: book.sourceKey)
            let urlRequest: URLRequest
            if let localURL = url.toAidokuFileUrl() {
                urlRequest = URLRequest(url: localURL)
            } else if let source {
                urlRequest = await source.getModifiedImageRequest(url: url, context: nil)
            } else {
                urlRequest = URLRequest(url: url)
            }
            guard !Task.isCancelled else { return }
            var processors: [ImageProcessing] = [DownsampleProcessor(width: 512)]
            if let source, source.features.processesCovers {
                processors.append(CoverInterceptorProcessor(source: source))
            }
            let request = ImageRequest(urlRequest: urlRequest, processors: processors,
                                      userInfo: [.processesKey: source?.features.processesCovers ?? false])
            guard let image = try? await ImagePipeline.shared.image(for: request),
                  !Task.isCancelled, self.loadedURL == url else { return }
            self.hasCoverImage = true
            self.frontMaterial.diffuse.contents = self.coverTexture(image: image)
            self.onTextureChanged?()
        }
    }

    var onTextureChanged: (() -> Void)?

    func cancelCoverLoad() { coverTask?.cancel(); coverTask = nil }

    private func buildGeometry() {
        let width = SumiBookPileLayout.bookWidth
        let height = SumiBookPileLayout.bookHeight
        let depth = SumiBookPileLayout.bookDepth
        let color = UIColor(book.presentation.accentColor)
        let boardMaterial = material(color)
        let pageMaterial = material(Self.pageEdgeTexture())
        let pages = SCNBox(width: width - 0.075, height: height - 0.085, length: depth - 0.055, chamferRadius: 0.012)
        pages.materials = [pageMaterial]
        addChildNode(SCNNode(geometry: pages))

        frontMaterial.lightingModel = .physicallyBased
        frontMaterial.roughness.contents = 0.86
        frontMaterial.metalness.contents = 0
        let front = SCNBox(width: width, height: height, length: 0.028, chamferRadius: 0.018)
        front.materials = [frontMaterial, boardMaterial, boardMaterial, boardMaterial, boardMaterial, boardMaterial]
        let frontNode = SCNNode(geometry: front)
        frontNode.position.z = Float(depth / 2 - 0.014)
        addChildNode(frontNode)

        let back = SCNBox(width: width, height: height, length: 0.028, chamferRadius: 0.018)
        back.materials = [boardMaterial]
        let backNode = SCNNode(geometry: back)
        backNode.position.z = Float(-depth / 2 + 0.014)
        addChildNode(backNode)

        let spine = SCNBox(width: 0.065, height: height - 0.02, length: depth - 0.015, chamferRadius: 0.025)
        spine.materials = [boardMaterial]
        let spineNode = SCNNode(geometry: spine)
        spineNode.position.x = Float(-width / 2 + 0.028)
        addChildNode(spineNode)

        let hull = SCNBox(width: width, height: height, length: depth, chamferRadius: 0.015)
        let body = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: hull, options: nil))
        body.mass = 0.5
        body.friction = 0.65
        body.rollingFriction = 0.6
        body.restitution = 0.12
        body.damping = 0.86
        body.angularDamping = 0.9
        body.angularVelocityFactor = SCNVector3(0, 0, 1)
        body.allowsResting = true
        body.categoryBitMask = 2
        body.collisionBitMask = 3
        physicsBody = body
    }

    private func material(_ contents: Any) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = contents
        material.lightingModel = .physicallyBased
        material.roughness.contents = 0.92
        material.metalness.contents = 0
        return material
    }

    private func coverTexture(image: UIImage?) -> UIImage {
        let size = CGSize(width: 512, height: 744)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let rect = CGRect(origin: .zero, size: size)
            UIColor(book.presentation.accentColor).setFill()
            context.fill(rect)
            if let image, image.size.width > 0, image.size.height > 0 {
                let scale = max(size.width / image.size.width, size.height / image.size.height)
                let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2,
                                      width: drawn.width, height: drawn.height))
            } else {
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byWordWrapping
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 47, weight: .bold),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraph
                ]
                (book.title as NSString).draw(in: CGRect(x: 38, y: 62, width: 436, height: 520), withAttributes: attributes)
                if let author = book.author {
                    (author as NSString).draw(in: CGRect(x: 38, y: 634, width: 436, height: 80),
                                             withAttributes: [.font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.white])
                }
            }
            let cg = context.cgContext
            cg.setFillColor(UIColor.black.withAlphaComponent(0.15).cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: 15, height: size.height))
            cg.setFillColor(UIColor.white.withAlphaComponent(0.18).cgColor)
            cg.fill(CGRect(x: 17, y: 0, width: 3, height: size.height))
            cg.setStrokeColor(UIColor.black.withAlphaComponent(0.12).cgColor)
            cg.setLineWidth(2)
            cg.stroke(rect.insetBy(dx: 1, dy: 1))
        }
    }

    private static func pageEdgeTexture() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 64, height: 128), format: format).image { context in
            UIColor(red: 0.96, green: 0.945, blue: 0.90, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 128))
            context.cgContext.setStrokeColor(UIColor(red: 0.64, green: 0.61, blue: 0.55, alpha: 0.28).cgColor)
            context.cgContext.setLineWidth(0.7)
            for y in stride(from: 2, through: 128, by: 4) {
                context.cgContext.move(to: CGPoint(x: 0, y: y))
                context.cgContext.addLine(to: CGPoint(x: 64, y: y))
            }
            context.cgContext.strokePath()
        }
    }
}
#endif
