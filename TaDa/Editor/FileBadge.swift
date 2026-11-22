import SwiftUI

/// A page with a folded corner holding a file's extension in capitals: what an attachment that isn't an image shows where an
/// image's thumbnail would be. It scales from a 28 × 34 design to `height`.
struct FileBadge: View {
    let ext: String
    let height: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        let scale = height / 34
        let tint = theme.color(\.link)
        ZStack(alignment: .top) {
            Page().fill(tint.opacity(theme.isDark ? 0.2 : 0.14))
            Page().stroke(tint.opacity(0.8), lineWidth: scale)
            Fold().stroke(tint.opacity(0.8), lineWidth: scale)
            Text(ext.uppercased())
                .font(.system(size: (ext.count == 4 ? 7.5 : 8) * scale, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.color(\.strong))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(width: 24 * scale)
                .alignmentGuide(.top) { $0[.firstTextBaseline] - 26 * scale }
        }
        .frame(width: 28 * scale, height: height, alignment: .top)
        .accessibilityHidden(true)
    }

    /// The page's outline in the 28 × 34 design, scaled to the rectangle it is drawn in.
    private nonisolated struct Page: Shape {
        func path(in rect: CGRect) -> Path {
            let s = rect.height / 34
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
            var path = Path()
            path.move(to: point(4, 1))
            path.addLine(to: point(18, 1))
            path.addLine(to: point(27, 10))
            path.addLine(to: point(27, 30))
            path.addArc(tangent1End: point(27, 33), tangent2End: point(24, 33), radius: 3 * s)
            path.addLine(to: point(4, 33))
            path.addArc(tangent1End: point(1, 33), tangent2End: point(1, 30), radius: 3 * s)
            path.addLine(to: point(1, 4))
            path.addArc(tangent1End: point(1, 1), tangent2End: point(4, 1), radius: 3 * s)
            path.closeSubpath()
            return path
        }
    }

    /// The folded corner's edge.
    private nonisolated struct Fold: Shape {
        func path(in rect: CGRect) -> Path {
            let s = rect.height / 34
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
            var path = Path()
            path.move(to: point(18, 1))
            path.addLine(to: point(18, 7))
            path.addArc(tangent1End: point(18, 10), tangent2End: point(21, 10), radius: 3 * s)
            path.addLine(to: point(27, 10))
            return path
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        FileBadge(ext: "pdf", height: 68)
        FileBadge(ext: "docx", height: 68)
        FileBadge(ext: "numbers", height: 68)
    }
    .padding()
}
