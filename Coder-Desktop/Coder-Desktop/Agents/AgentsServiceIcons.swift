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
                // SwiftUI `Menu` bridges to NSMenu, which draws the item image at the
                // NSImage's own size and ignores `.frame()`. Setting `.size` alone is
                // unreliable for SVG-backed reps, so render into a real 16×16 bitmap.
                let resized = Self.menuIcon(from: image)
                Task { @MainActor in self?.mcpIconsByServer[id] = resized }
            }
        }
    }
}
