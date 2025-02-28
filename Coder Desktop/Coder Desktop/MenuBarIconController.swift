import FluidMenuBarExtra
import NetworkExtension
import SwiftUI

@MainActor
class MenuBarController {
    let menuBarExtra: FluidMenuBarExtra
    private let onImage = NSImage(named: "MenuBarIcon")!
    private let offOpacity = CGFloat(0.3)
    private let onOpacity = CGFloat(1.0)

    private var animationTask: Task<Void, Never>?

    init(menuBarExtra: FluidMenuBarExtra) {
        self.menuBarExtra = menuBarExtra
        // Off by default, as `vpnDidUpdate` isn't called until the VPN is configured
        menuBarExtra.setOpacity(offOpacity)
    }

    func vpnDidUpdate(_ connection: NETunnelProviderSession) {
        switch connection.status {
        case .connected:
            stopAnimation()
            menuBarExtra.setOpacity(onOpacity)
        case .connecting, .reasserting, .disconnecting:
            startAnimation()
        case .invalid, .disconnected:
            stopAnimation()
            menuBarExtra.setOpacity(offOpacity)
        @unknown default:
            stopAnimation()
            menuBarExtra.setOpacity(offOpacity)
        }
    }

    func startAnimation() {
        if animationTask != nil { return }
        animationTask = Task {
            defer { animationTask = nil }
            let totalFrames = 60
            let cycleDurationMs: UInt64 = 2000
            let frameDurationMs = cycleDurationMs / UInt64(totalFrames - 1)
            repeat {
                for frame in 0 ..< totalFrames {
                    if Task.isCancelled { break }
                    let progress = Double(frame) / Double(totalFrames - 1)
                    let alpha = 0.3 + 0.7 * (0.5 - 0.5 * cos(2 * Double.pi * progress))
                    menuBarExtra.setOpacity(CGFloat(alpha))
                    try? await Task.sleep(for: .milliseconds(frameDurationMs))
                }
            } while !Task.isCancelled
        }
    }

    func stopAnimation() {
        animationTask?.cancel()
        animationTask = nil
    }
}
