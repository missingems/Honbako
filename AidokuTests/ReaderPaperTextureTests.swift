//
//  ReaderPaperTextureTests.swift
//  AidokuTests
//

@testable import Aidoku
import AsyncDisplayKit
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct ReaderPaperTextureTests {
    @Test("Paper grain has visible neutral variation and a stable point size on every display")
    func deterministicGrain() {
        let data = ReaderPaperTexture.tileData()
        #expect(data == ReaderPaperTexture.tileData())
        #expect(data != ReaderPaperTexture.tileData(seed: 42))
        #expect(data.count == ReaderPaperTexture.tileSize * ReaderPaperTexture.tileSize * 4)
        let bytes = [UInt8](data)
        let alpha = stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] }
        #expect(Set(alpha).count > 24)
        #expect(alpha.allSatisfy { $0 <= 80 })
        #expect(alpha.contains { $0 >= 65 })
        let mean = Double(alpha.reduce(0) { $0 + Int($1) }) / Double(alpha.count)
        #expect(mean > 20 && mean < 27)
        #expect(alpha.contains(0)) // White highlights survive the stronger relief.
        #expect(Double(alpha.filter { $0 > 65 }.count) / Double(alpha.count) < 0.02)
        let lightData = ReaderPaperTexture.tileData(strength: .light)
        let lightAlpha = stride(from: 3, to: lightData.count, by: 4).map { Double(lightData[$0]) }
        let lightMean = lightAlpha.reduce(0, +) / Double(lightAlpha.count)
        let lightVariance = lightAlpha.reduce(0) { $0 + pow($1 - lightMean, 2) } / Double(lightAlpha.count)
        let strongVariance = alpha.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(alpha.count)
        #expect(strongVariance > lightVariance * 4) // More texture contrast, not just a gray wash.
        for scale: CGFloat in [1, 2, 3] {
            #expect(ReaderPaperTexture.image(displayScale: scale)?.size == CGSize(
                width: ReaderPaperTexture.tilePointSize, height: ReaderPaperTexture.tilePointSize
            ))
        }
        for channel in 0..<3 {
            #expect(stride(from: channel, to: bytes.count, by: 4).allSatisfy { bytes[$0] == 0 })
        }
    }

    @Test("Every strength preserves solid black ink and neutral paper", arguments: ReaderPaperTextureStrength.allCases)
    func inkContrast(strength: ReaderPaperTextureStrength) throws {
        let black = try compositedPixels(white: false, strength: strength)
        let white = try compositedPixels(white: true, strength: strength)
        let blackValues = stride(from: 0, to: black.count, by: 4).map { black[$0] }
        let whiteValues = stride(from: 0, to: white.count, by: 4).map { white[$0] }
        #expect(blackValues.allSatisfy { $0 == 0 })
        #expect(whiteValues.allSatisfy { $0 >= 175 && $0 <= 255 })
        #expect(Set(whiteValues).count > 24)
        #expect(stride(from: 0, to: white.count, by: 4).allSatisfy {
            white[$0] == white[$0 + 1] && white[$0] == white[$0 + 2]
        })
    }

    @Test("Texture follows artwork bounds, stays out of letterboxes, and never captures touches")
    func artworkBounds() {
        let texture = ReaderPaperTextureView()
        texture.update(
            imageSize: CGSize(width: 200, height: 100),
            in: CGRect(x: 0, y: 0, width: 200, height: 400),
            contentMode: .scaleAspectFit
        )
        #expect(texture.frame == CGRect(x: 0, y: 150, width: 200, height: 100))
        #expect(!texture.isUserInteractionEnabled)
        #expect(texture.accessibilityElementsHidden)
        texture.update(
            imageSize: CGSize(width: 200, height: 400),
            in: CGRect(x: 0, y: 0, width: 200, height: 400),
            contentMode: .scaleToFill
        )
        #expect(texture.frame == CGRect(x: 0, y: 0, width: 200, height: 400))
    }

    @Test("The preference updates an existing texture immediately and hides it without artwork")
    func livePreference() {
        let key = AppSettings.reader.paperTexture.key
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            UserDefaults.standard.set(previous, forKey: key)
            NotificationCenter.default.post(name: .init(key), object: nil)
        }
        #expect(!AppSettings.reader.paperTexture.defaultValue)
        setTexture(false)
        let texture = ReaderPaperTextureView()
        texture.update(imageSize: CGSize(width: 100, height: 100), in: CGRect(x: 0, y: 0, width: 100, height: 100), contentMode: .scaleAspectFit)
        #expect(texture.isHidden)
        setTexture(true)
        #expect(!texture.isHidden)
        #expect(texture.backgroundColor != nil)
        texture.update(imageSize: nil, in: texture.bounds, contentMode: .scaleAspectFit)
        #expect(texture.isHidden)
    }

    @Test("A paged manga keeps original image pixels and text pages have no texture")
    func originalImageAndText() async throws {
        let key = AppSettings.reader.paperTexture.key
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            UserDefaults.standard.set(previous, forKey: key)
            NotificationCenter.default.post(name: .init(key), object: nil)
        }
        setTexture(true)
        let store = ReaderTemporaryPageStore()
        do {
            let page = ReaderPageView(temporaryPageStore: store)
            page.frame = CGRect(x: 0, y: 0, width: 200, height: 400)
            let original = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 40)).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 20, height: 40))
            }
            page.setPageImage(original)
            page.layoutIfNeeded()
            let texture = try #require(page.imageView.subviews.compactMap { $0 as? ReaderPaperTextureView }.first)
            #expect(!texture.isHidden)
            #expect(page.imageView.image === original)
            page.setPageText(text: "Readable text remains unchanged.")
            #expect(texture.isHidden)
            #expect(page.imageView.image == nil)
        } catch {
            await store.removeAll()
            throw error
        }
        await store.removeAll()
    }

    @Test("The actual single and spread reader hierarchy renders visible grain over white artwork", arguments: [false, true])
    func renderedReaderTexture(isSpread: Bool) async throws {
        let key = AppSettings.reader.paperTexture.key
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            UserDefaults.standard.set(previous, forKey: key)
            NotificationCenter.default.post(name: .init(key), object: nil)
        }
        let store = ReaderTemporaryPageStore()
        do {
            let first = ReaderPageViewController(type: .page, delegate: nil, temporaryPageStore: store)
            let second = ReaderPageViewController(type: .page, delegate: nil, temporaryPageStore: store)
            let controller: UIViewController = isSpread
                ? ReaderDoublePageViewController(firstPage: first, secondPage: second, direction: .ltr)
                : first
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 600, height: 600))
            window.rootViewController = controller
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            controller.loadViewIfNeeded()
            let original = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 400)).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 200, height: 400))
            }
            let pages = isSpread ? [first, second] : [first]
            for page in pages { page.pageView?.setPageImage(original) }
            window.layoutIfNeeded()
            controller.view.layoutIfNeeded()
            controller.view.layoutIfNeeded()
            for controller in pages {
                let page = try #require(controller.pageView)
                #expect(!page.imageView.bounds.isEmpty)
                setTexture(false)
                let plain = try renderedRedValues(page.imageView)
                setTexture(true)
                let textured = try renderedRedValues(page.imageView)
                #expect(plain.allSatisfy { $0 >= 254 })
                #expect(Set(textured).count > 16)
                #expect(textured.contains { $0 <= 225 })
                #expect(page.imageView.image === original)
            }
        } catch {
            await store.removeAll()
            throw error
        }
        await store.removeAll()
    }

    @Test("Webtoon image nodes share the live texture without replacing their image")
    func webtoonTexture() throws {
        let key = AppSettings.reader.paperTexture.key
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            UserDefaults.standard.set(previous, forKey: key)
            NotificationCenter.default.post(name: .init(key), object: nil)
        }
        setTexture(true)
        let node = GIFImageNode()
        node.contentMode = .scaleToFill
        let original = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 40)).image { _ in }
        node.image = original
        let texture = try #require(node.view.subviews.compactMap { $0 as? ReaderPaperTextureView }.first)
        #expect(!texture.isHidden)
        #expect(node.image === original)
        setTexture(false)
        #expect(texture.isHidden)
    }

    @Test("Strength increases visible contrast and updates the live overlay without replacing artwork")
    func liveStrength() throws {
        let strengthKey = AppSettings.reader.paperTextureStrength.key
        let toggleKey = AppSettings.reader.paperTexture.key
        let previousStrength = UserDefaults.standard.object(forKey: strengthKey)
        let previousToggle = UserDefaults.standard.object(forKey: toggleKey)
        defer {
            UserDefaults.standard.set(previousStrength, forKey: strengthKey)
            UserDefaults.standard.set(previousToggle, forKey: toggleKey)
            NotificationCenter.default.post(name: .init(strengthKey), object: nil)
            NotificationCenter.default.post(name: .init(toggleKey), object: nil)
        }
        #expect(AppSettings.reader.paperTextureStrength.defaultValue == .strong)
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 128, height: 128))
        host.backgroundColor = .white
        let texture = ReaderPaperTextureView()
        host.addSubview(texture)
        texture.update(imageSize: host.bounds.size, in: host.bounds, contentMode: .scaleToFill)
        setTexture(true)
        var means: [Double] = []
        for strength in ReaderPaperTextureStrength.allCases {
            AppSettings.reader.paperTextureStrength.set(strength)
            NotificationCenter.default.post(name: .init(strengthKey), object: nil)
            #expect(AppSettings.reader.paperTextureStrength.get() == strength)
            let pixels = try renderedRedValues(host)
            means.append(Double(pixels.reduce(0) { $0 + Int($1) }) / Double(pixels.count))
        }
        #expect(means[0] > means[1] && means[1] > means[2])
        #expect(means[0] - means[2] > 8)
        #expect(ReaderPaperTexture.tileData(strength: .light) != ReaderPaperTexture.tileData(strength: .strong))
    }

    private func setTexture(_ enabled: Bool) {
        AppSettings.reader.paperTexture.set(enabled)
        NotificationCenter.default.post(name: .init(AppSettings.reader.paperTexture.key), object: nil)
    }

    private func renderedRedValues(_ view: UIView) throws -> [UInt8] {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { context in
            view.layer.render(in: context.cgContext)
        }
        let cgImage = try #require(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try #require(CGContext(
                data: bytes.baseAddress, width: cgImage.width, height: cgImage.height,
                bitsPerComponent: 8, bytesPerRow: cgImage.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        }
        return stride(from: 0, to: pixels.count, by: 4).map { pixels[$0] }
    }

    private func compositedPixels(white: Bool, strength: ReaderPaperTextureStrength = .strong) throws -> [UInt8] {
        let tile = try #require(ReaderPaperTexture.image(displayScale: 1, strength: strength)?.cgImage)
        let size = ReaderPaperTexture.tileSize
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try #require(CGContext(
                data: bytes.baseAddress, width: size, height: size,
                bitsPerComponent: 8, bytesPerRow: size * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            let value: CGFloat = white ? 1 : 0
            context.setFillColor(red: value, green: value, blue: value, alpha: 1)
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            context.fill(rect)
            context.draw(tile, in: rect)
        }
        return pixels
    }
}
