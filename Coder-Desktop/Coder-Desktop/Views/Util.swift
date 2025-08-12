import Combine
import SwiftUI

// This is required for inspecting stateful views
final class Inspection<V> {
    let notice = PassthroughSubject<UInt, Never>()
    var callbacks = [UInt: (V) -> Void]()

    func visit(_ view: V, _ line: UInt) {
        if let callback = callbacks.removeValue(forKey: line) {
            callback(view)
        }
    }
}

extension UUID {
    var uuidData: Data {
        withUnsafePointer(to: uuid) {
            Data(bytes: $0, count: MemoryLayout.size(ofValue: uuid))
        }
    }

    init?(uuidData: Data) {
        guard uuidData.count == 16 else {
            return nil
        }
        var uuid: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &uuid) {
            $0.copyBytes(from: uuidData)
        }
        self.init(uuid: uuid)
    }
}

public extension View {
    @inlinable nonisolated func onHoverWithPointingHand(perform action: @escaping (Bool) -> Void) -> some View {
        onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
            action(hovering)
        }
    }
}

@MainActor
private struct ActivationPolicyModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            // This lets us show and hide the app from the dock and cmd+tab
            // when a window is open.
            .onAppear {
                NSApp.setActivationPolicy(.regular)
            }
            .onDisappear {
                if NSApp.windows.filter { $0.level != .statusBar && $0.isVisible }.count <= 1 {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
    }
}

public extension View {
    func showDockIconWhenOpen() -> some View {
        modifier(ActivationPolicyModifier())
    }
}
