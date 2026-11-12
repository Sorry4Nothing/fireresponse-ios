import CoreGraphics
import UIKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FireResponse

@MainActor
struct SignOutTests {
    /// Ohne Adresse erreicht der Aufruf den Server nie: gelöscht wird trotzdem alles.
    @Test func signOutClearsEverythingLocal() async {
        let sessions = InMemorySessionStore(cookie: "session=abc")
        let client = ApiClient(baseURL: nil, appVersion: "1.0.0", store: sessions)
        let model = AppModel(api: FireResponseAPI(client: client))
        model.phase = .ready
        // swiftlint:disable:next line_length
        let json = #"{"id":"x1","name":"Alex Muster","benutzername":"alex","kantonsadmin":false,"zweiterFaktor":false,"einwilligung":true,"mussPasswortAendern":false,"pushProgramme":true,"einheiten":[],"teilnehmende":[]}"#
        model.profile = try? JSONDecoder.api.decode(Profile.self, from: Data(json.utf8))
        #expect(model.profile != nil)
        let store = MemoryLockStore(Data([1, 1]))
        let lock = AppLockController(authenticator: FakeBiometrics(), store: store)
        var cachesCleared = false

        await SignOut.perform(model: model, lock: lock, clearCaches: { cachesCleared = true })

        #expect(sessions.read() == nil)
        #expect(store.baseline == nil)
        #expect(!lock.isEnabled)
        #expect(lock.status == .unlocked)
        #expect(cachesCleared)
        #expect(model.profile == nil)
        #expect(model.phase == .signedOut)
    }
}

struct ProfileImageTests {
    /// Rauschbild: lässt sich schlecht komprimieren und ist gross genug, um die Verkleinerung zu erzwingen.
    private func noisyJPEG(side: Int) throws -> Data {
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for index in pixels.indices { pixels[index] = UInt8.random(in: 0...255) }
        let image = try #require(pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage()
        })
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func size(of data: Data) throws -> (width: Int, height: Int) {
        let props = try #require(CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] })
        return (props[kCGImagePropertyPixelWidth] as? Int ?? 0, props[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }

    @Test func cropsToSquareJPEGWithoutMetadata() throws {
        let result = try #require(ProfileImageResizer.jpeg(from: noisyJPEG(side: 1500), crop: ProfileImageCrop()))
        #expect(result.starts(with: [0xFF, 0xD8]))
        let dimensions = try size(of: result)
        #expect(dimensions.width == 512 && dimensions.height == 512)
    }

    @Test func rejectsDataThatIsNoImage() {
        #expect(ProfileImageResizer.jpeg(from: Data("kein Bild".utf8), crop: ProfileImageCrop()) == nil)
        #expect(ProfileImageResizer.preview(from: Data("kein Bild".utf8)) == nil)
    }

    @Test func defaultCropIsTheCenterSquare() {
        let square = ProfileImageCrop().square(width: 400, height: 300)
        #expect(square == CGRect(x: 50, y: 0, width: 300, height: 300))
    }

    @Test func zoomShrinksTheSquare() {
        let square = ProfileImageCrop(zoom: 2).square(width: 400, height: 300)
        #expect(square == CGRect(x: 125, y: 75, width: 150, height: 150))
    }

    @Test func movingStopsAtTheEdge() {
        let crop = ProfileImageCrop(zoom: 2).moved(dx: 10_000, dy: -10_000, width: 400, height: 300)
        #expect(crop.square(width: 400, height: 300) == CGRect(x: 250, y: 0, width: 150, height: 150))
    }

    @Test func zoomIsLimited() {
        #expect(ProfileImageCrop().zoomed(to: 9, width: 400, height: 300).zoom == ProfileImageCrop.maxZoom)
        #expect(ProfileImageCrop().zoomed(to: 0.2, width: 400, height: 300).zoom == 1)
    }
}

@MainActor
struct SVGRasterizerTests {
    private let circle = Data(##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><circle cx="50" cy="50" r="48" fill="#1B2A5C"/></svg>"##.utf8)

    @Test func recognisesSVGButNotPNG() {
        #expect(SVGRasterizer.isSVG(circle))
        #expect(SVGRasterizer.isSVG(Data(#"<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg"/>"#.utf8)))
        #expect(!SVGRasterizer.isSVG(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])))
        #expect(!SVGRasterizer.isSVG(Data("kein Bild".utf8)))
    }

    @Test func drawsSVGIntoAReadableImage() async throws {
        let png = try #require(await SVGRasterizer.png(from: circle, size: CGSize(width: 80, height: 80)))
        let image = try #require(UIImage(data: png))
        #expect(image.size.width > 0 && image.size.height > 0)
        // Der Kreis ist gefüllt: Das Bild ist nicht leer.
        let pixel = try #require(image.cgImage.flatMap { $0.dataProvider?.data as Data? })
        #expect(pixel.contains { $0 != 0 })
    }

    @Test func nonSVGPassesThroughUnchanged() async {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        #expect(await SVGRasterizer.displayable(bytes, size: CGSize(width: 40, height: 40)) == bytes)
    }
}
