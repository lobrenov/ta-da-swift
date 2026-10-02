/// Changes one checkbox by replacing only the character between its brackets.
public enum ChecklistEditor {
    /// Nil when `marker` isn't in the reference set, or the text no longer has `box` where it was scanned.
    public static func setMarker(_ marker: Character, of box: Checkbox, in text: String) -> String? {
        guard Checkbox.State(marker: marker) != nil, let newByte = marker.asciiValue,
              let oldByte = box.marker.asciiValue else { return nil }
        var bytes = Array(text.utf8)
        var lineStart = 0
        for _ in 0..<box.lineIndex {
            guard let newline = bytes[lineStart...].firstIndex(of: UInt8(ascii: "\n")) else { return nil }
            lineStart = newline + 1
        }
        let i = lineStart + box.column
        guard box.column >= 1, i + 1 < bytes.count, bytes[i - 1] == UInt8(ascii: "["),
              bytes[i] == oldByte, bytes[i + 1] == UInt8(ascii: "]") else { return nil }
        bytes[i] = newByte
        return String(decoding: bytes, as: UTF8.self)
    }

    /// A click completes an open box (`[x]`) and reopens a done or cancelled one (`[ ]`).
    /// Nil for icon-only boxes, which ignore clicks, and for stale boxes.
    public static func click(_ box: Checkbox, in text: String) -> String? {
        switch box.state {
        case .open: setMarker("x", of: box, in: text)
        case .done, .cancelled: setMarker(" ", of: box, in: text)
        case .icon: nil
        }
    }
}
