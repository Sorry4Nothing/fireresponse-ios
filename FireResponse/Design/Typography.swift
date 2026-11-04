import SwiftUI

// Barlow Condensed nur für Titel (wächst mit Dynamic Type über relativeTo), sonst SF Pro über die Textstile.
extension Font {
    private static func barlow(_ size: CGFloat, weight: String, relativeTo style: Font.TextStyle) -> Font {
        .custom("BarlowCondensed-\(weight)", size: size, relativeTo: style)
    }

    static let frDisplay = barlow(40, weight: "ExtraBold", relativeTo: .largeTitle)
    static let frLargeTitle = barlow(34, weight: "ExtraBold", relativeTo: .largeTitle)
    static let frTitle1 = barlow(28, weight: "ExtraBold", relativeTo: .title)
    static let frTitle2 = barlow(22, weight: "ExtraBold", relativeTo: .title2)
    static let frDay = barlow(26, weight: "ExtraBold", relativeTo: .title2).monospacedDigit()
    static let frCardTitle = barlow(17, weight: "Bold", relativeTo: .headline)
}
