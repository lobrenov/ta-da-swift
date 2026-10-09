// An area's symbol: a cube with its top face filled at 30%, in `doing`.
import SwiftUI

struct AreaIcon: View {
    /// 16 in the sidebar, 24 by a page's title, 13 in a chip.
    var size: CGFloat = 16
    /// The stroke on the cube's 16-point grid; thinner at title size.
    var lineWidth: CGFloat? = nil
    var tint: KeyPath<Theme, PlatformColor> = \.doing
    @Environment(\.theme) private var theme

    var body: some View {
        let scale = size / 16
        let width = (lineWidth ?? (size >= 20 ? 1.25 : 1.45)) * scale
        ZStack {
            Top().fill(.opacity(0.3))
            Top().stroke(style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            Outline().stroke(style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
        .foregroundStyle(theme.color(tint))
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// The top face: M8 1.8 l5.6 3.1 L8 8 2.4 4.9 z on a 16-point grid.
    nonisolated private struct Top: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.addLines([(8, 1.8), (13.6, 4.9), (8, 8), (2.4, 4.9)].map { point($0, in: rect) })
                path.closeSubpath()
            }
        }
    }

    /// The hexagon round the cube, and the front edge.
    nonisolated private struct Outline: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.addLines([(8, 1.8), (13.6, 4.9), (13.6, 11.1), (8, 14.2), (2.4, 11.1), (2.4, 4.9)].map { point($0, in: rect) })
                path.closeSubpath()
                path.move(to: point((8, 8), in: rect))
                path.addLine(to: point((8, 14.2), in: rect))
            }
        }
    }
}

nonisolated private func point(_ xy: (CGFloat, CGFloat), in rect: CGRect) -> CGPoint {
    CGPoint(x: rect.minX + xy.0 * rect.width / 16, y: rect.minY + xy.1 * rect.height / 16)
}
