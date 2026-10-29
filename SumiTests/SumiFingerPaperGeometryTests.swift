@testable import Sumi
import Testing
import UIKit

struct SumiFingerPaperGeometryTests {
    @Test("The held point follows horizontal finger travel without acceleration or a jump")
    func heldPointTracksFinger() {
        for width: CGFloat in [210, 450, 700] {
            for gripFraction: CGFloat in [0.35, 0.7, 1] {
                let grip = CGPoint(x: width * gripFraction, y: 200)
                let paper = SumiPageCurlDeformation(size: CGSize(width: width, height: 650), grip: grip)
                #expect(paper.progress(horizontalTranslation: 0) == 0)
                #expect(paper.progress(horizontalTranslation: -2 * grip.x) == 1)
                var previous: CGFloat = 0
                for fraction in stride(from: CGFloat(0.02), through: 0.98, by: 0.02) {
                    let translation = -2 * grip.x * fraction
                    let p = paper.progress(horizontalTranslation: translation)
                    let point = paper.vertex(x: grip.x, y: grip.y, progress: p).paper
                    let projected = point.x
                    #expect(abs(projected - (grip.x + translation)) < 0.02)
                    #expect(p >= previous)
                    previous = p
                }
            }
        }
    }

    @Test("Top and bottom pulls bend different corners while keeping the binding pinned")
    func cornerAndVerticalMotion() {
        let size = CGSize(width: 450, height: 650)
        let top = SumiPageCurlDeformation(size: size, grip: CGPoint(x: 430, y: 40), verticalBend: 80)
        let bottom = SumiPageCurlDeformation(size: size, grip: CGPoint(x: 430, y: 610), verticalBend: -80)
        for paper in [top, bottom] {
            for y: CGFloat in [0, 200, 650] {
                for p: CGFloat in [0, 0.1, 0.4, 0.7, 1] {
                    let bound = paper.vertex(x: 0, y: y, progress: p)
                    #expect(bound.paper.x == 0 && bound.paper.elevation == 0 && bound.y == y)
                }
                let first = paper.vertex(x: 450, y: y, progress: 0)
                let last = paper.vertex(x: 450, y: y, progress: 1)
                #expect(abs(first.paper.x - 450) < 0.001 && first.y == y)
                #expect(abs(last.paper.x + 450) < 0.001 && abs(last.y - y) < 0.001)
            }
        }
        let a = top.vertex(x: 450, y: 0, progress: 0.4)
        let b = bottom.vertex(x: 450, y: 0, progress: 0.4)
        #expect(abs(a.paper.x - b.paper.x) > 2)
        #expect(a.y > 0 && b.y < 0)
    }

    @Test("Paper fibres keep their lengths and remain orthogonal during every pull")
    func paperNeverStretchesOrShears() {
        for size in [CGSize(width: 450, height: 650), CGSize(width: 650, height: 450)] {
            for corner: CGFloat in [0.05, 0.25, 0.5, 0.75, 0.95] {
                for pull: CGFloat in [-0.4, 0, 0.4] {
                    let surface = SumiPageCurlDeformation(size: size,
                        grip: CGPoint(x: size.width * 0.65, y: size.height * corner), verticalBend: size.height * pull)
                    for p: CGFloat in [0.01, 0.15, 0.35, 0.5, 0.65, 0.85, 0.99] {
                        for u: CGFloat in [0.1, 0.49, 0.7, 0.95] {
                            let x = size.width * u, y = size.height * 0.6, step: CGFloat = 0.01
                            func point(_ x: CGFloat, _ y: CGFloat) -> [CGFloat] {
                                let value = surface.vertex(x: x, y: y, progress: p)
                                return [value.paper.x, value.y, value.paper.elevation]
                            }
                            let a = point(x, y), b = point(x + step, y), c = point(x, y + step)
                            let dx = zip(b, a).map { ($0 - $1) / step }, dy = zip(c, a).map { ($0 - $1) / step }
                            #expect(abs(dx.reduce(0) { $0 + $1 * $1 } - 1) < 0.002)
                            #expect(abs(dy.reduce(0) { $0 + $1 * $1 } - 1) < 0.002)
                            #expect(abs(zip(dx, dy).reduce(0) { $0 + $1.0 * $1.1 }) < 0.002)
                        }
                    }
                }
            }
        }
    }

    @Test("Reversing a two-dimensional pull restores exactly the same mesh")
    func reversibleSurface() {
        var paper = SumiPageCurlDeformation(size: CGSize(width: 450, height: 650), grip: CGPoint(x: 410, y: 530))
        paper.verticalBend = -65
        let p = paper.progress(horizontalTranslation: -280)
        let before = paper.vertex(x: 330, y: 470, progress: p)
        _ = paper.vertex(x: 330, y: 470, progress: paper.progress(horizontalTranslation: -500))
        let restored = paper.vertex(x: 330, y: 470, progress: paper.progress(horizontalTranslation: -280))
        #expect(before.paper.x == restored.paper.x && before.paper.elevation == restored.paper.elevation)
        #expect(before.y == restored.y)
    }
}
