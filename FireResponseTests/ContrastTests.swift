import SwiftUI
import Testing
import UIKit

/// Prüft die Farb-Tokens des Asset Catalogs in allen vier Erscheinungen (Nacht, Tag, je Mehr Kontrast) nach WCAG 2.2.
struct ContrastTests {
    private static let surfaces = ["surface", "surface-container-low", "surface-container", "surface-container-high"]

    private static let appearances: [(name: String, traits: UITraitCollection)] = [
        ("Nacht", .init(userInterfaceStyle: .dark)),
        ("Tag", .init(userInterfaceStyle: .light)),
        ("Nacht, Mehr Kontrast", UITraitCollection(traitsFrom: [.init(userInterfaceStyle: .dark), .init(accessibilityContrast: .high)])),
        ("Tag, Mehr Kontrast", UITraitCollection(traitsFrom: [.init(userInterfaceStyle: .light), .init(accessibilityContrast: .high)]))
    ]

    /// Textpaare (Vordergrund, Hintergrund), mindestens 4.5:1.
    private static var textPairs: [(String, String)] {
        let onSurface = ["on-surface", "on-surface-variant", "accent-text", "accent", "primary-text", "on-error-container"]
        var pairs = onSurface.flatMap { fg in surfaces.map { (fg, $0) } }
        pairs += [
            ("on-primary", "primary"), ("on-secondary", "secondary"), ("on-secondary-muted", "secondary"),
            ("on-accent-fill", "accent-fill"), ("on-secondary-container", "secondary-container"),
            ("on-success-container", "success-container"), ("on-error-container", "error-container"),
            ("on-warning-container", "warning-container"), ("on-rang-container", "rang-container")
        ]
        return pairs
    }

    /// Nicht-Text (Rand, Fokusring, Schalter), mindestens 3:1.
    private static var graphicPairs: [(String, String)] {
        ["outline", "focus", "switch-on"].flatMap { fg in surfaces.map { (fg, $0) } }
    }

    private func rgb(_ name: String, _ traits: UITraitCollection) throws -> (Double, Double, Double) {
        let color = try #require(UIColor(named: name, in: .main, compatibleWith: traits), "Farbe \(name) fehlt")
        var (r, g, b, a) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        color.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }

    private func luminance(_ c: (Double, Double, Double)) -> Double {
        func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.0) + 0.7152 * lin(c.1) + 0.0722 * lin(c.2)
    }

    private func ratio(_ fg: String, _ bg: String, _ traits: UITraitCollection) throws -> Double {
        let (l1, l2) = (luminance(try rgb(fg, traits)), luminance(try rgb(bg, traits)))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    @Test func textPairsReach4_5() throws {
        for (appearance, traits) in Self.appearances {
            for (fg, bg) in Self.textPairs {
                let value = try ratio(fg, bg, traits)
                #expect(value >= 4.5, "\(appearance): \(fg) auf \(bg) = \(String(format: "%.2f", value)):1")
            }
        }
    }

    @Test func graphicsReach3() throws {
        for (appearance, traits) in Self.appearances {
            for (fg, bg) in Self.graphicPairs {
                let value = try ratio(fg, bg, traits)
                #expect(value >= 3, "\(appearance): \(fg) auf \(bg) = \(String(format: "%.2f", value)):1")
            }
        }
    }
}
