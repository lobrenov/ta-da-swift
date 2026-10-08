import SwiftUI

/// The checkboxes of the editor and task rows, from the Inline markdown checkboxes artboard: a 16pt
/// rounded box in the marker's tint with a glyph inside. Done and Important fill the box and draw the
/// glyph in `bg`.
nonisolated enum InlineCheckbox {
    private struct Glyph {
        var stroke: CGPath?
        var fill: CGPath?
        var filledBox = false
    }

    /// Draws `marker`'s box into a flipped (y-down) context.
    static func draw(_ marker: Character, in rect: CGRect, tint: PlatformColor, background: PlatformColor, context: CGContext) {
        let glyph = glyphs[marker] ?? Glyph()
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / 16, y: rect.height / 16)
        context.setLineWidth(1.5)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let box = CGPath(roundedRect: CGRect(x: 0.75, y: 0.75, width: 14.5, height: 14.5),
                         cornerWidth: 3.25, cornerHeight: 3.25, transform: nil)
        if glyph.filledBox {
            context.addPath(box)
            context.setFillColor(tint.cgColor)
            context.fillPath()
        }
        context.addPath(box)
        context.setStrokeColor(tint.cgColor)
        context.strokePath()

        let ink = glyph.filledBox ? background.cgColor : tint.cgColor
        if let stroke = glyph.stroke {
            context.addPath(stroke)
            context.setStrokeColor(ink)
            context.strokePath()
        }
        if let fill = glyph.fill {
            context.addPath(fill)
            context.setFillColor(ink)
            context.fillPath()
        }
    }

    /// The artboard's glyphs: SVG paths on a 16-unit grid whose box spans 1–15, so they scale
    /// by 16/14 about the centre to sit in the 16pt box. Immutable once built.
    nonisolated(unsafe) private static let glyphs: [Character: Glyph] = {
        let specs: [Character: (stroke: String, fill: String, filledBox: Bool)] = [
            "x": ("M5 8.2l2 2 4-4.4", "", true),
            "X": ("M5 8.2l2 2 4-4.4", "", true),
            "/": ("", "M5.5 5.5h5v5h-5z", false),
            "-": ("M5.2 10.8l5.6-5.6", "", false),
            // Blocked: task rows only; `[B]` isn't a body marker.
            "B": ("M4.6 8h6.8", "", false),
            ">": ("M5 8h6M8.6 5.6L11 8l-2.4 2.4", "", false),
            "<": ("M5 6.2h6v5.2H5zM5 8.2h6M6.8 4.6v2M9.2 4.6v2", "", false),
            "?": ("M6.3 6.4a1.8 1.8 0 1 1 2.5 1.6c-.5.3-.8.6-.8 1.1",
                  "M7.35 11.1a.65.65 0 1 0 1.3 0a.65.65 0 1 0-1.3 0z", false),
            "!": ("M8 4.9v3.6", "M7.3 10.9a.7.7 0 1 0 1.4 0a.7.7 0 1 0-1.4 0z", true),
            "*": ("", "M8 4.4l1.1 2.2 2.4.35-1.75 1.7.42 2.4L8 9.9l-2.17 1.15.42-2.4L4.5 6.95l2.4-.35z", false),
            "\"": ("", "M4.9 6.3h2.5v2.4c0 1.3-.7 2.2-2 2.6v-.9c.6-.3.9-.7.9-1.3H4.9zM8.6 6.3h2.5v2.4c0 1.3-.7 2.2-2 2.6v-.9c.6-.3.9-.7.9-1.3H8.6z", false),
            "l": ("M8 11.6s2.8-2.4 2.8-4.5a2.8 2.8 0 0 0-5.6 0c0 2.1 2.8 4.5 2.8 4.5z",
                  "M7.3 7.1a.7.7 0 1 0 1.4 0a.7.7 0 1 0-1.4 0z", false),
            "b": ("M5.8 4.7h4.4v6.7L8 9.9l-2.2 1.5z", "", false),
            "i": ("M8 7.5v3.3", "M7.3 5.5a.7.7 0 1 0 1.4 0a.7.7 0 1 0-1.4 0z", false),
            "S": ("M8 4.4v7.2M9.8 6c-.3-.5-1-.8-1.8-.8-1 0-1.7.5-1.7 1.2 0 1.6 3.5.8 3.5 2.4 0 .7-.8 1.2-1.8 1.2-.8 0-1.5-.3-1.8-.8", "", false),
            "I": ("M6.9 11.5h2.2M7 10.1h2c0-.9 1.6-1.4 1.6-3a2.6 2.6 0 0 0-5.2 0c0 1.6 1.6 2.1 1.6 3z", "", false),
            "p": ("M5 7.6h1.3v3.8H5zM6.3 7.6l1.5-2.8c.7 0 1.1.5 1 1.1l-.2 1.3h1.8c.6 0 1 .5.9 1.1l-.5 2.2c-.1.5-.5.9-1 .9H6.3", "", false),
            "c": ("M5 8.4h1.3V4.6H5zM6.3 8.4l1.5 2.8c.7 0 1.1-.5 1-1.1l-.2-1.3h1.8c.6 0 1-.5.9-1.1l-.5-2.2c-.1-.5-.5-.9-1-.9H6.3", "", false),
            "f": ("M8 11.6c1.6 0 2.7-1 2.7-2.5 0-1.8-1.6-2.6-1.6-4.5-1.2.7-1.6 1.8-1.6 2.6-.5-.3-.8-.8-.9-1.3-.8.8-1.3 1.8-1.3 3.2 0 1.5 1.1 2.5 2.7 2.5z", "", false),
            "k": ("M5 9.7a1.6 1.6 0 1 0 3.2 0a1.6 1.6 0 1 0-3.2 0zM7.5 8.5l3.3-3.3M9.6 6.4l1 1", "", false),
            "w": ("M6 4.8h4v2.4a2 2 0 0 1-4 0zM6 5.6H4.8c0 1.2.5 1.8 1.4 1.9M10 5.6h1.2c0 1.2-.5 1.8-1.4 1.9M8 9.2v1.7M6.5 11.3h3", "", false),
            "u": ("M4.8 10.4l2.4-2.4 1.4 1.4 2.6-2.8M9.2 6.6h2v2", "", false),
            "d": ("M4.8 5.6l2.4 2.4 1.4-1.4 2.6 2.8M9.2 9.4h2v-2", "", false),
        ]
        var toBox = CGAffineTransform(translationX: 8, y: 8).scaledBy(x: 16 / 14, y: 16 / 14).translatedBy(x: -8, y: -8)
        func path(_ d: String) -> CGPath? {
            d.isEmpty ? nil : SVGPath.parse(d).copy(using: &toBox)
        }
        return specs.mapValues { Glyph(stroke: path($0.stroke), fill: path($0.fill), filledBox: $0.filledBox) }
    }()
}

nonisolated extension Theme {
    /// The Inline markdown checkboxes artboard's tint for `marker`, Ta Da's `[B]` included.
    func checkboxTint(_ marker: Character) -> PlatformColor {
        switch marker {
        case " ", "-", "\"": muted
        case "x", "X", "S", "p", "u": done
        case "/", "?": doing
        case "B", "b", "f": blocked
        case ">", "i": accent
        case "<", "*", "I", "k", "w": due
        case "!", "c", "d": deadline
        case "l": link
        default: fg
        }
    }
}

/// `InlineCheckbox` as a view, filling its frame.
struct InlineCheckboxView: View {
    let marker: Character
    let tint: PlatformColor
    let background: PlatformColor

    var body: some View {
        Canvas { context, size in
            context.withCGContext { cg in
                InlineCheckbox.draw(marker, in: CGRect(origin: .zero, size: size), tint: tint,
                                    background: background, context: cg)
            }
        }
    }
}

/// Parses SVG path data (M L H V C S A Z, absolute and relative). Arcs must be circular and unrotated.
nonisolated enum SVGPath {
    static func parse(_ d: String) -> CGPath {
        let tokens = d.matches(of: /[A-Za-z]|-?(?:\d*\.\d+|\d+)/).map { String(d[$0.range]) }
        let path = CGMutablePath()
        var i = 0
        var command: Character = "M"
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint?

        func number() -> CGFloat {
            defer { i += 1 }
            return CGFloat(Double(tokens[i]) ?? 0)
        }
        func point(_ relative: Bool) -> CGPoint {
            let x = number(), y = number()
            return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        while i < tokens.count {
            if let letter = tokens[i].first, letter.isLetter {
                command = letter
                i += 1
            } else if command == "Z" || command == "z" {
                break
            }
            let relative = command.isLowercase
            var control: CGPoint?
            switch command.uppercased() {
            case "M":
                current = point(relative)
                start = current
                path.move(to: current)
                command = relative ? "l" : "L"
            case "L":
                current = point(relative)
                path.addLine(to: current)
            case "H":
                let x = number()
                current.x = relative ? current.x + x : x
                path.addLine(to: current)
            case "V":
                let y = number()
                current.y = relative ? current.y + y : y
                path.addLine(to: current)
            case "C", "S":
                let c1: CGPoint
                if command.uppercased() == "C" {
                    c1 = point(relative)
                } else {
                    c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                }
                let c2 = point(relative), end = point(relative)
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end
                control = c2
            case "A":
                var radius = number()
                _ = number()  // ry: arcs are circular
                _ = number()  // x-axis rotation: always 0
                let largeArc = number() != 0, sweep = number() != 0
                let end = point(relative)
                // Centre from the endpoints (SVG spec, F.6.5, with rx = ry and no rotation).
                let half = CGPoint(x: (current.x - end.x) / 2, y: (current.y - end.y) / 2)
                let halfSquared = half.x * half.x + half.y * half.y
                radius = max(radius, halfSquared.squareRoot())
                let k = (largeArc == sweep ? -1 : 1) * max(0, (radius * radius - halfSquared) / halfSquared).squareRoot()
                let center = CGPoint(x: k * half.y + (current.x + end.x) / 2, y: -k * half.x + (current.y + end.y) / 2)
                path.addArc(center: center, radius: radius,
                            startAngle: atan2(current.y - center.y, current.x - center.x),
                            endAngle: atan2(end.y - center.y, end.x - center.x),
                            clockwise: !sweep)
                current = end
            case "Z":
                path.closeSubpath()
                current = start
            default:
                return path
            }
            lastControl = control
        }
        return path
    }
}
