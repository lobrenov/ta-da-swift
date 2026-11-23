import SwiftUI

/// The parent chip's icons, drawn into the editor's flipped (y-down) context: a project's progress ring and an area's cube,
/// as `ProgressRing` and `AreaIcon` draw them.
nonisolated enum TaskAttributeIcons {
    /// A ring with its done part as a pie.
    static func ring(fraction: Double, in rect: CGRect, tint: PlatformColor, context: CGContext) {
        let side = min(rect.width, rect.height) * 12 / 14
        let box = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(tint.cgColor)
        context.setLineWidth(1.4)
        context.strokeEllipse(in: box.insetBy(dx: 0.7, dy: 0.7))
        guard fraction > 0 else { return }
        let center = CGPoint(x: box.midX, y: box.midY)
        context.move(to: center)
        context.addArc(center: center, radius: side / 2, startAngle: -.pi / 2, endAngle: -.pi / 2 + 2 * .pi * min(fraction, 1), clockwise: false)
        context.closePath()
        context.setFillColor(tint.cgColor)
        context.fillPath()
    }

    /// A cube with its top face filled at 30%, on a 16-point grid.
    static func cube(in rect: CGRect, tint: PlatformColor, context: CGContext) {
        func path(_ points: [(CGFloat, CGFloat)], closed: Bool = true) -> CGPath {
            let path = CGMutablePath()
            path.addLines(between: points.map { CGPoint(x: $0.0, y: $0.1) })
            if closed { path.closeSubpath() }
            return path
        }
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / 16, y: rect.height / 16)
        let top = path([(8, 1.8), (13.6, 4.9), (8, 8), (2.4, 4.9)])
        context.addPath(top)
        context.setFillColor(tint.withAlphaComponent(0.3).cgColor)
        context.fillPath()
        context.setStrokeColor(tint.cgColor)
        context.setLineWidth(1.45)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(top)
        context.addPath(path([(8, 1.8), (13.6, 4.9), (13.6, 11.1), (8, 14.2), (2.4, 11.1), (2.4, 4.9)]))
        context.addPath(path([(8, 8), (8, 14.2)], closed: false))
        context.strokePath()
    }
}
