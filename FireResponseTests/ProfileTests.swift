import CoreGraphics
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

    @Test func shrinksLargeImageBelowFiveMebibytes() throws {
        let original = try noisyJPEG(side: 3000)
        #expect(original.count > ProfileImageResizer.maxBytes)
        let result = try #require(ProfileImageResizer.jpeg(from: original))
        #expect(result.count <= ProfileImageResizer.maxBytes)
        #expect(result.starts(with: [0xFF, 0xD8]))
        let size = try #require(CGImageSourceCreateWithData(result as CFData, nil).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] })
        #expect((size[kCGImagePropertyPixelWidth] as? Int ?? .max) <= 1024)
    }

    @Test func keepsShrinkingUntilTheLimitHolds() throws {
        let original = try noisyJPEG(side: 1500)
        let limit = 60_000
        let result = try #require(ProfileImageResizer.jpeg(from: original, maxBytes: limit))
        #expect(result.count <= limit)
    }

    @Test func rejectsDataThatIsNoImage() {
        #expect(ProfileImageResizer.jpeg(from: Data("kein Bild".utf8)) == nil)
    }
}
