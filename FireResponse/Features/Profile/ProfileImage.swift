import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Bereitet ein gewähltes Foto für `PUT /api/v1/ich/bild` vor: der gewählte Ausschnitt als JPEG mit 512 px (weit unter den 5 MiB des Vertrags).
/// Das neu kodierte JPEG enthält keine EXIF-Daten mehr (kein Aufnahmeort), und die Drehung ist schon eingerechnet (SR Bildupload).
nonisolated enum ProfileImageResizer {
    /// Seitenlänge des hochgeladenen Ausschnitts; der Server skaliert danach auf 256 px.
    static let outputSide = 512
    /// Längste Seite, auf die das Foto fürs Zuschneiden gelesen wird: genügt für 4-fachen Zoom auf 512 px.
    private static let workSide = 3072
    private static let previewSide = 1024

    /// Das Foto fürs Zuschneiden: aufrecht gedreht, höchstens 1024 px.
    static func preview(from data: Data) -> CGImage? { upright(data, maxSide: previewSide) }

    /// Der gewählte Ausschnitt als JPEG mit 512 × 512 px, ohne EXIF; `nil`, wenn die Datei kein lesbares Bild ist.
    static func jpeg(from data: Data, crop: ProfileImageCrop) -> Data? {
        guard let photo = upright(data, maxSide: workSide) else { return nil }
        let square = crop.square(width: photo.width, height: photo.height)
        guard let part = photo.cropping(to: square),
              let context = CGContext(
                data: nil, width: outputSide, height: outputSide, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return nil }
        context.interpolationQuality = .high
        // Transparenz wird weiss, wie auf Android.
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: outputSide, height: outputSide))
        context.draw(part, in: CGRect(x: 0, y: 0, width: outputSide, height: outputSide))
        return context.makeImage().flatMap { encode($0, quality: 0.88) }
    }

    private static func upright(_ data: Data, maxSide: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func encode(_ image: CGImage, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}

/// Der Ausschnitt, den die Person wählt: Mitte als Anteil von Breite und Höhe (0 bis 1) und Zoom ab 1 (1 = grösstes Quadrat).
nonisolated struct ProfileImageCrop: Equatable {
    static let maxZoom = 4.0

    var centerX = 0.5
    var centerY = 0.5
    var zoom = 1.0

    /// Seitenlänge und linke obere Ecke des Quadrats im Foto, in Pixeln.
    func square(width: Int, height: Int) -> CGRect {
        let side = max(1, Int(Double(min(width, height)) / min(max(zoom, 1), Self.maxZoom)))
        let x = min(max(Int(centerX * Double(width) - Double(side) / 2), 0), width - side)
        let y = min(max(Int(centerY * Double(height) - Double(side) / 2), 0), height - side)
        return CGRect(x: x, y: y, width: side, height: side)
    }

    /// Mitte und Zoom so, dass der Ausschnitt im Foto liegt: Wer über den Rand schiebt, bleibt am Rand.
    func normalized(width: Int, height: Int) -> ProfileImageCrop {
        let square = square(width: width, height: height)
        return ProfileImageCrop(centerX: square.midX / Double(width), centerY: square.midY / Double(height), zoom: min(max(zoom, 1), Self.maxZoom))
    }

    /// Verschiebt den Ausschnitt um Pixel des Fotos.
    func moved(dx: Double, dy: Double, width: Int, height: Int) -> ProfileImageCrop {
        ProfileImageCrop(centerX: centerX + dx / Double(width), centerY: centerY + dy / Double(height), zoom: zoom)
            .normalized(width: width, height: height)
    }

    func zoomed(to value: Double, width: Int, height: Int) -> ProfileImageCrop {
        ProfileImageCrop(centerX: centerX, centerY: centerY, zoom: value).normalized(width: width, height: height)
    }
}
