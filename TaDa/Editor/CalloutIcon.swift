import SwiftUI
import TaDaCore

/// The callout icons from the Callouts artboard: SVG paths on a 16-unit grid, stroked at 1.6 with round ends.
/// Quote's marks are filled.
nonisolated enum CalloutIcon {
    /// Draws `type`'s icon into a flipped (y-down) context.
    static func draw(_ type: CalloutType, in rect: CGRect, tint: PlatformColor, context: CGContext) {
        guard let paths = paths[type] else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / 16, y: rect.height / 16)
        if let stroke = paths.stroke {
            context.addPath(stroke)
            context.setStrokeColor(tint.cgColor)
            context.setLineWidth(1.6)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.strokePath()
        }
        if let fill = paths.fill {
            context.addPath(fill)
            context.setFillColor(tint.cgColor)
            context.fillPath()
        }
    }

    /// Immutable once built.
    nonisolated(unsafe) private static let paths: [CalloutType: (stroke: CGPath?, fill: CGPath?)] = {
        let specs: [CalloutType: (stroke: String, fill: String)] = [
            .note: ("M10.6 2.4l3 3L6 13H3v-3zM9.1 3.9l3 3", ""),
            .abstract: ("M5.6 2.2h4.8v2.4H5.6zM5.6 3.2H3.6v10.6h8.8V3.2h-2M5.8 8h4.4M5.8 11h2.8", ""),
            .info: ("M8 1.8a6.2 6.2 0 1 0 0 12.4a6.2 6.2 0 1 0 0-12.4zM8 7.3v3.7M8 5h.01", ""),
            .todo: ("M8 1.8a6.2 6.2 0 1 0 0 12.4a6.2 6.2 0 1 0 0-12.4zM5.4 8.2l1.8 1.8 3.4-3.6", ""),
            .tip: ("M8 14.2c2.3 0 4-1.5 4-3.7 0-2.6-2.4-3.8-2.4-6.7-1.8 1-2.4 2.6-2.4 3.8-.7-.4-1.2-1.1-1.3-1.9C4.7 6.8 4 8.4 4 10.5c0 2.2 1.7 3.7 4 3.7z", ""),
            .success: ("M3 8.4l3.2 3.2L13 4.6", ""),
            .question: ("M8 1.8a6.2 6.2 0 1 0 0 12.4a6.2 6.2 0 1 0 0-12.4zM6.2 6.2a1.9 1.9 0 1 1 2.6 1.8c-.5.2-.8.6-.8 1.1v.3M8 11.3h.01", ""),
            .warning: ("M8 2.2l6.1 10.9H1.9zM8 6.4v3M8 11.1h.01", ""),
            .failure: ("M4.2 4.2l7.6 7.6M11.8 4.2l-7.6 7.6", ""),
            .danger: ("M9 1.8L3.6 9H8l-1 5.2L12.4 7H8z", ""),
            .bug: ("M5.4 6.6h5.2v3.6a2.6 2.6 0 0 1-5.2 0zM6.4 6.6V5.2a1.6 1.6 0 0 1 3.2 0v1.4M2.8 8.8h2.6M10.6 8.8h2.6M3.4 5.6l2 1.1M12.6 5.6l-2 1.1M3.4 12.6l2.2-1.2M12.6 12.6l-2.2-1.2M8 9v3.6", ""),
            .example: ("M6.2 4h7.2M6.2 8h7.2M6.2 12h7.2M2.8 4h.01M2.8 8h.01M2.8 12h.01", ""),
            .quote: ("", "M2.6 4.4h4.2v4c0 2-1 3.4-3.1 3.9v-1.4c.9-.4 1.4-1 1.5-2H2.6zM9.2 4.4h4.2v4c0 2-1 3.4-3.1 3.9v-1.4c.9-.4 1.4-1 1.5-2H9.2z"),
        ]
        return specs.mapValues { ($0.stroke.isEmpty ? nil : SVGPath.parse($0.stroke), $0.fill.isEmpty ? nil : SVGPath.parse($0.fill)) }
    }()
}

nonisolated extension Theme {
    /// The colour of a callout type, from the design framework's Callouts table.
    func calloutTint(_ type: CalloutType) -> PlatformColor {
        switch type {
        case .note, .info, .todo: accent
        case .abstract, .tip: doing
        case .success: done
        case .question: due
        case .warning: blocked
        case .failure, .danger, .bug: deadline
        case .example: link
        case .quote: muted
        }
    }
}

/// `CalloutIcon` as a view, filling its frame.
struct CalloutIconView: View {
    let type: CalloutType
    let tint: PlatformColor

    var body: some View {
        Canvas { context, size in
            context.withCGContext { cg in
                CalloutIcon.draw(type, in: CGRect(origin: .zero, size: size), tint: tint, context: cg)
            }
        }
    }
}
