import SwiftUI

struct NoteScaledFont: ViewModifier {
    @ScaledMetric private var scaledSize: CGFloat

    private let baseSize: CGFloat
    private let maximumScale: CGFloat?
    let weight: Font.Weight
    let design: Font.Design

    init(
        size: CGFloat,
        weight: Font.Weight,
        design: Font.Design,
        relativeTo textStyle: Font.TextStyle,
        maximumScale: CGFloat? = nil
    ) {
        _scaledSize = ScaledMetric(
            wrappedValue: size,
            relativeTo: textStyle
        )
        baseSize = size
        self.maximumScale = maximumScale
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        let resolvedSize = maximumScale.map { min(scaledSize, baseSize * $0) } ?? scaledSize
        content.font(
            .system(
                size: resolvedSize,
                weight: weight,
                design: design
            )
        )
    }
}

extension View {
    func noteFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> some View {
        modifier(
            NoteScaledFont(
                size: size,
                weight: weight,
                design: design,
                relativeTo: textStyle
            )
        )
    }

    /// Caps only the largest accessibility sizes while retaining the normal
    /// Dynamic Type curve. This is reserved for compact chrome (brand and
    /// navigation labels); body copy remains fully scalable.
    func noteFontCapped(
        size: CGFloat,
        maximumScale: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> some View {
        modifier(
            NoteScaledFont(
                size: size,
                weight: weight,
                design: design,
                relativeTo: textStyle,
                maximumScale: maximumScale
            )
        )
    }
}
