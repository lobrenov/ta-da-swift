// The views of an attachment that the Mac and iPhone share: a where-line, the large preview and the image's pixel size.
import SwiftUI
import ImageIO
import TaDaCore

/// A where-line with the file titles tinted.
struct AttachmentWhereText: View {
    let line: AttachmentWhere
    let linkTint: KeyPath<Theme, PlatformColor>
    @Environment(\.theme) private var theme

    var body: some View {
        if line.titles.isEmpty {
            Text(line.prefix)
        } else {
            Text("\(line.prefix)\(Text(line.titles).foregroundStyle(theme.color(linkTint)))\(line.suffix)")
        }
    }
}

/// An image shown whole in a rounded box; an icon while it isn't there to read.
struct AttachmentPreview: View {
    let url: URL?
    var cornerRadius: CGFloat = 10
    @State private var decoded: CGImage?
    @Environment(\.theme) private var theme

    var body: some View {
        Color.clear
            .frame(height: 270)
            .frame(maxWidth: .infinity)
            .overlay {
                if let decoded {
                    Image(decorative: decoded, scale: 1).resizable().scaledToFit()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(theme.color(\.muted))
                        .opacity(url == nil ? 0.25 : 1)
                }
            }
            .background(theme.color(\.code))
            .clipShape(.rect(cornerRadius: cornerRadius))
            .accessibilityHidden(true)
            .task(id: url) {
                decoded = nil
                guard let url else { return }
                decoded = await ThumbnailCache.load(url, pixels: 1600)
            }
    }
}

/// An image's pixel size, read from its header.
nonisolated enum ImageMetadata {
    @concurrent static func pixelSize(of url: URL) async -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }
}
