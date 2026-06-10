import AppKit
import CoderSDK
import SDWebImage

extension CoderAgentsService {
    func mcpIcon(_ id: UUID) -> NSImage? {
        mcpIconsByServer[id]
    }

    /// Cached 16×16 icon for a workspace app, by its (resolved) icon URL.
    func workspaceAppIcon(_ url: URL?) -> NSImage? {
        guard let url else { return nil }
        return workspaceAppIcons[url.absoluteString]
    }

    /// Fetches workspace-app icons (svg/png) and caches them at menu size, like MCP icons.
    func loadWorkspaceAppIcons(_ urls: [URL]) {
        for url in urls where workspaceAppIcons[url.absoluteString] == nil {
            let key = url.absoluteString
            SDWebImageManager.shared.loadImage(
                with: url, options: [], progress: nil
            ) { [weak self] image, _, _, _, _, _ in
                guard let image else { return }
                let resized = Self.menuIcon(from: image)
                Task { @MainActor in self?.workspaceAppIcons[key] = resized }
            }
        }
    }

    /// Flattens an arbitrarily-sized (possibly SVG) image into a fixed 16×16 menu icon.
    nonisolated static func menuIcon(from image: NSImage, side: CGFloat = 16) -> NSImage {
        let target = NSImage(size: NSSize(width: side, height: side))
        target.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(x: 0, y: 0, width: side, height: side),
            from: .zero, operation: .sourceOver, fraction: 1.0
        )
        target.unlockFocus()
        return target
    }

    /// Whether an icon is a SINGLE-color glyph (every opaque pixel grayscale AND roughly the
    /// same luminance) — only those should be tinted to the label color. Grayscale art with
    /// internal contrast (e.g. Notion's black cube + white N) must NOT be templated: template
    /// rendering keeps only the alpha channel, flattening it into a solid blob.
    nonisolated static func isMonochrome(_ image: NSImage) -> Bool {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return false }
        let width = rep.pixelsWide, height = rep.pixelsHigh
        guard width > 0, height > 0 else { return false }
        var sawOpaque = false
        var minLum = 1.0, maxLum = 0.0
        for y in stride(from: 0, to: height, by: max(1, height / 16)) {
            for x in stride(from: 0, to: width, by: max(1, width / 16)) {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.1 else { continue }
                sawOpaque = true
                let (r, g, b) = (color.redComponent, color.greenComponent, color.blueComponent)
                if max(r, g, b) - min(r, g, b) > 0.12 { return false }
                let lum = (Double(r) + Double(g) + Double(b)) / 3
                minLum = min(minLum, lum)
                maxLum = max(maxLum, lum)
            }
        }
        return sawOpaque && maxLum - minLum < 0.3
    }

    /// Fetches connector icons (svg/png/webp) via SDWebImage (the SVG coder is registered
    /// at launch), like the web UI. Relative `/icon/…` paths resolve against the host.
    func loadMCPIcons() {
        for server in mcpServers {
            guard let raw = server.icon_url,
                  let url = URL(string: raw, relativeTo: client?.url)?.absoluteURL,
                  mcpIconsByServer[server.id] == nil
            else { continue }
            let id = server.id
            SDWebImageManager.shared.loadImage(
                with: url, options: [], progress: nil
            ) { [weak self] image, _, _, _, _, _ in
                guard let image else { return }
                // Render into a real 16×16 bitmap (NSMenu draws at the image's own size and
                // ignores `.frame()`; `.size` alone is unreliable for SVG reps).
                let resized = Self.menuIcon(from: image)
                // Many connector glyphs are monochrome white (built for dark UI) and vanish on a
                // light background. Flagging the grayscale ones as templates makes them render in
                // the label color, so they adapt to the theme; colorful icons keep their color.
                resized.isTemplate = Self.isMonochrome(image)
                Task { @MainActor in self?.mcpIconsByServer[id] = resized }
            }
        }
    }
}
