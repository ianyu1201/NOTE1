import SwiftUI

struct NoteScaledFont: ViewModifier {
    @ScaledMetric private var scaledSize: CGFloat

    let weight: Font.Weight
    let design: Font.Design

    init(
        size: CGFloat,
        weight: Font.Weight,
        design: Font.Design,
        relativeTo textStyle: Font.TextStyle
    ) {
        _scaledSize = ScaledMetric(
            wrappedValue: size,
            relativeTo: textStyle
        )
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(
            .system(
                size: scaledSize,
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
}
