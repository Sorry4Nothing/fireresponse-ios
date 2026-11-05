import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Bereitet ein gewähltes Foto für `PUT /api/v1/ich/bild` vor: höchstens 5 MiB (Vertrag), als JPEG, längste Seite höchstens 1024 px.
/// Das neu kodierte JPEG enthält keine EXIF-Daten mehr (kein Aufnahmeort), und die Drehung ist schon eingerechnet (SR Bildupload).
nonisolated enum ProfileImageResizer {
    static let maxBytes = 5 * 1024 * 1024

    static func jpeg(from data: Data, maxBytes: Int = ProfileImageResizer.maxBytes, maxSide: Int = 1024) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        var side = maxSide
        while side >= 64 {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: side,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            for quality in [0.85, 0.7, 0.5, 0.3] {
                if let encoded = encode(image, quality: quality), encoded.count <= maxBytes { return encoded }
            }
            side /= 2
        }
        return nil
    }

    private static func encode(_ image: CGImage, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
