import CoderSDK
import RoyalVNCKit
import SwiftUI

/// Native remote desktop for the chat's workspace. RoyalVNC (raw RFB) connects to the agent's
/// on-demand `portabledesktop` (Xvnc) session through a local WebSocket↔TCP relay; the
/// WebSocket rides the Coder Connect tunnel straight to the agent (no coderd hop) and opening
/// it is what starts the desktop — the same lazy start the web UI uses. Requires Coder Connect.
struct VNCPanel: View {
    /// The workspace's Coder Connect hostname, e.g. `my-workspace.coder`.
    let host: String
    @StateObject private var model = VNCModel()

    var body: some View {
        ZStack {
            VNCContainerView(model: model)
            switch model.status {
            case .connecting:
                overlay("Connecting to desktop…", systemImage: "display", spinner: true)
            case let .failed(message):
                overlay(message, systemImage: "bolt.horizontal.circle", spinner: false)
            case .idle, .connected:
                EmptyView()
            }
        }
        .task(id: host) { await model.start(host: host) }
        .onDisappear { model.stop() }
        .id(host)
    }

    private func overlay(_ text: String, systemImage: String, spinner: Bool) -> some View {
        VStack(spacing: 8) {
            if spinner {
                ProgressView().controlSize(.large)
            } else {
                Image(systemName: systemImage).font(.largeTitle).foregroundStyle(.secondary)
            }
            Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

/// Owns the relay + RoyalVNC connection and hosts the framebuffer view. The actual
/// `VNCConnectionDelegate` is a separate non-isolated object that hops back here on the main
/// actor (RoyalVNC delivers callbacks off-main with non-Sendable types).
@MainActor
final class VNCModel: ObservableObject {
    enum Status: Equatable {
        case idle, connecting, connected, failed(String)
    }

    @Published var status: Status = .idle
    /// The container the framebuffer view is added into once the connection produces one.
    let container = NSView()

    private var relay: VNCWebSocketRelay?
    private var connection: VNCConnection?
    private var delegate: VNCConnectionDelegateProxy?

    func start(host: String) async {
        guard status == .idle else { return }
        status = .connecting

        let request = AgentClient(agentHost: host).desktopVNCRequest()
        let relay = VNCWebSocketRelay(request: request) { [weak self] message in
            Task { @MainActor in self?.relayClosed(message) }
        }
        self.relay = relay

        let port: UInt16
        do {
            port = try await relay.start()
        } catch {
            status = .failed("Couldn't reach the workspace desktop. Is Coder Connect connected?")
            return
        }

        let settings = VNCConnection.Settings(
            isDebugLoggingEnabled: false,
            hostname: "127.0.0.1",
            port: port,
            isShared: true,
            isScalingEnabled: true,
            useDisplayLink: true,
            inputMode: .forwardKeyboardShortcutsIfNotInUseLocally,
            isClipboardRedirectionEnabled: true,
            colorDepth: .depth24Bit,
            frameEncodings: .default
        )
        let connection = VNCConnection(settings: settings)
        let delegate = VNCConnectionDelegateProxy(model: self)
        connection.delegate = delegate
        self.connection = connection
        self.delegate = delegate
        connection.connect()
    }

    func stop() {
        connection?.disconnect()
        connection = nil
        delegate = nil
        relay?.stop()
        relay = nil
        container.subviews.forEach { $0.removeFromSuperview() }
        status = .idle
    }

    // MARK: Delegate callbacks (already hopped to the main actor)

    func presentFramebuffer(_ framebuffer: VNCFramebuffer, connection: VNCConnection) {
        guard let delegate else { return }
        let view = VNCCAFramebufferView(
            frame: container.bounds,
            framebuffer: framebuffer,
            connection: connection,
            connectionDelegate: delegate
        )
        view.autoresizingMask = [.width, .height]
        container.subviews.forEach { $0.removeFromSuperview() }
        container.addSubview(view)
        status = .connected
    }

    func connectionStateChanged(_ state: VNCConnection.ConnectionState) {
        switch state.status {
        case .connecting:
            if status == .idle { status = .connecting }
        case .disconnected:
            if let error = state.error as? VNCError, error.shouldDisplayToUser {
                status = .failed(error.localizedDescription)
            } else if status != .idle {
                status = .failed("Desktop disconnected.")
            }
            container.subviews.forEach { $0.removeFromSuperview() }
        default:
            break
        }
    }

    private func relayClosed(_ message: String?) {
        if let message, status != .connected { status = .failed(message) }
    }
}

/// Bridges RoyalVNC's off-main, non-Sendable delegate callbacks onto the main actor. The
/// framebuffer view re-assigns itself as the connection delegate and forwards the rest here.
private final class VNCConnectionDelegateProxy: NSObject, VNCConnectionDelegate, @unchecked Sendable {
    weak var model: VNCModel?

    init(model: VNCModel) { self.model = model }

    func connection(_: VNCConnection, stateDidChange state: VNCConnection.ConnectionState) {
        let transfer = Unchecked(state)
        Task { @MainActor [weak model] in model?.connectionStateChanged(transfer.value) }
    }

    func connection(
        _: VNCConnection,
        credentialFor _: VNCAuthenticationType,
        completion: @escaping (VNCCredential?) -> Void
    ) {
        completion(nil) // portabledesktop's Xvnc runs with SecurityTypes None — no auth.
    }

    func connection(_ connection: VNCConnection, didCreateFramebuffer framebuffer: VNCFramebuffer) {
        let transfer = Unchecked((framebuffer, connection))
        Task { @MainActor [weak model] in model?.presentFramebuffer(transfer.value.0, connection: transfer.value.1) }
    }

    func connection(_ connection: VNCConnection, didResizeFramebuffer framebuffer: VNCFramebuffer) {
        let transfer = Unchecked((framebuffer, connection))
        Task { @MainActor [weak model] in model?.presentFramebuffer(transfer.value.0, connection: transfer.value.1) }
    }

    // swiftlint:disable:next function_parameter_count
    func connection(
        _: VNCConnection, didUpdateFramebuffer _: VNCFramebuffer,
        x _: UInt16, y _: UInt16, width _: UInt16, height _: UInt16
    ) {} // consumed by VNCCAFramebufferView

    func connection(_: VNCConnection, didUpdateCursor _: VNCCursor) {} // consumed by the view
}

/// Escape hatch for handing RoyalVNC's non-Sendable reference types to the main actor; safe
/// because they're only used on the main actor after the hop and RoyalVNC owns their lifetime.
private struct Unchecked<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// Hosts the model's framebuffer container in SwiftUI.
private struct VNCContainerView: NSViewRepresentable {
    let model: VNCModel

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        view.addSubview(model.container)
        model.container.frame = view.bounds
        model.container.autoresizingMask = [.width, .height]
        return view
    }

    func updateNSView(_: NSView, context _: Context) {}
}
