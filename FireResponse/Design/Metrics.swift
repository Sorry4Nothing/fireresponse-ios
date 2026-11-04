import SwiftUI

// Abstände, Grössen und Ecken aus den Tokens (pt, 4-pt-Raster).
enum Spacing {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
    static let s8: CGFloat = 32
}

enum Sizes {
    /// Mindestgrösse jedes bedienbaren Elements.
    static let touchTarget: CGFloat = 44
    static let button: CGFloat = 52
    static let field: CGFloat = 50
    static let avatar: CGFloat = 44
    static let profileAvatar: CGFloat = 84
    static let contentMax: CGFloat = 640
}

enum Radius {
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 28
}

extension RoundedRectangle {
    /// Kontinuierliche Ecken, wie das Design sie verlangt.
    init(radius: CGFloat) { self.init(cornerRadius: radius, style: .continuous) }
}
