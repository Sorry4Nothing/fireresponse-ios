import SwiftUI

#if DEBUG
extension View {
    /// Rahmen für die Vorschauen: Erscheinung, Textgrösse und Grundfläche wie im Screen.
    func frPreview(_ scheme: ColorScheme, size: DynamicTypeSize = .accessibility5) -> some View {
        padding(Spacing.s4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.frSurface)
            .preferredColorScheme(scheme)
            .dynamicTypeSize(size)
    }
}
#endif
