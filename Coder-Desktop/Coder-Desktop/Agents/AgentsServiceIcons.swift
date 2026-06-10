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
    /// same luminance) — only those become template images, AppKit's native mechanism for
    /// label-colored, theme-adaptive glyphs. Grayscale art with internal contrast (e.g.
    /// Notion's black cube + white N) must NOT be templated: template rendering keeps only
    /// the alpha channel, flattening it into a solid blob.
    ///
    /// Renders once into a 16×16 sRGB bitmap and scans the raw bytes — deterministic
    /// colorspace and no per-pixel NSColor sampling.
    nonisolated static func isMonochrome(_ image: NSImage) -> Bool {
        let side = 16
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return false }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = ctx.data else { return false }
        let px = data.bindMemory(to: UInt8.self, capacity: side * side * 4)

        var sawOpaque = false
        var minLum = 255, maxLum = 0
        for i in stride(from: 0, to: side * side * 4, by: 4) {
            let alpha = Int(px[i + 3])
            guard alpha > 25 else { continue } // skip transparent + antialiased fringe
            sawOpaque = true
            // Un-premultiply so edge pixels compare on true color, not alpha-darkened values.
            let r = min(255, Int(px[i]) * 255 / alpha)
            let g = min(255, Int(px[i + 1]) * 255 / alpha)
            let b = min(255, Int(px[i + 2]) * 255 / alpha)
            if max(r, g, b) - min(r, g, b) > 30 { return false } // saturated color → keep as-is
            let lum = (r + g + b) / 3
            minLum = min(minLum, lum)
            maxLum = max(maxLum, lum)
        }
        return sawOpaque && maxLum - minLum < 75
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
