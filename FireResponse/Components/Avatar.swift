import SwiftUI

/// Runder Platzhalter mit Initialen oder Profilbild. Dekorativ: der Name steht daneben.
struct Avatar: View {
    enum Size {
        case list, profile
        var points: CGFloat { self == .list ? Sizes.avatar : Sizes.profileAvatar }
    }

    /// `solid` für Personen und Gruppen, `calm` für Kinder in Listen und Zusagen.
    enum Style { case solid, calm }

    let initials: String
    var size: Size = .list
    var style: Style = .solid
    var image: Image?

    init(initials: String, size: Size = .list, style: Style = .solid, image: Image? = nil) {
        self.initials = initials
        self.size = size
        self.style = style
        self.image = image
    }

    /// Profilbild als Daten (z. B. aus der API); fehlt oder ist es unlesbar, erscheinen die Initialen.
    init(initials: String, size: Size = .list, style: Style = .solid, imageData: Data?) {
        let image = imageData.flatMap(UIImage.init(data:)).map(Image.init(uiImage:))
        self.init(initials: initials, size: size, style: style, image: image)
    }

    var body: some View {
        Group {
            if let image {
                image.resizable().scaledToFill()
            } else {
                Text(initials)
                    .font(.system(size: size.points * 0.34, weight: .bold))
                    .foregroundStyle(style == .solid ? Color.frOnSecondary : .frOnSecondaryContainer)
            }
        }
        .frame(width: size.points, height: size.points)
        .background(style == .solid ? Color.frSecondary : .frSecondaryContainer)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }
}

#if DEBUG
private struct AvatarDemo: View {
    var body: some View {
        HStack(spacing: Spacing.s3) {
            Avatar(initials: "AM")
            Avatar(initials: "AM", style: .calm)
            Avatar(initials: "AM", size: .profile)
            Avatar(initials: "AM", size: .profile, style: .calm)
        }
    }
}

#Preview("Nacht, AX5") { AvatarDemo().frPreview(.dark) }
#Preview("Tag, AX5") { AvatarDemo().frPreview(.light) }
#endif
