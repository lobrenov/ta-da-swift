// Dynamic Type for the iPhone's fixed-size text: the design's point sizes are the sizes at the default text size,
// and grow and shrink in proportion with the user's.
#if os(iOS)
import SwiftUI

private struct ScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

private struct ScaledMinHeight: ViewModifier {
    @ScaledMetric private var height: CGFloat

    init(_ height: CGFloat) {
        _height = ScaledMetric(wrappedValue: height, relativeTo: .body)
    }

    func body(content: Content) -> some View {
        content.frame(minHeight: height)
    }
}

extension View {
    /// The system font at `size` points at the default text size, scaling with Dynamic Type.
    func scaledFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design))
    }

    /// At least `height` points tall at the default text size, scaling with Dynamic Type, so a control that pairs with
    /// text grows with it.
    func scaledMinHeight(_ height: CGFloat) -> some View {
        modifier(ScaledMinHeight(height))
    }
}
#endif
