import SwiftTerm
import SwiftUI

/// A native terminal into the chat's workspace, opened as a real local `ssh` session to
/// the workspace's Coder Connect hostname (e.g. `my-workspace.coder`). SwiftTerm's
/// `LocalProcessTerminalView` owns the local PTY and the ssh subprocess.
///
/// Requires Coder Connect to be running (that's what resolves `*.coder` and routes to the
/// agent) — so it connects from a signed build with the tunnel up, not the unsigned debug
/// build.
struct TerminalPanel: View {
    /// The workspace's Coder Connect hostname, e.g. `my-workspace.coder`.
    let host: String
    @StateObject private var signal = TerminalSignal()

    var body: some View {
        ZStack {
            SSHTerminalView(host: host, signal: signal)
            if signal.terminated {
                disconnected
            }
        }
        // A new host means a fresh session; clear any prior disconnect state.
        .id(host)
    }

    private var disconnected: some View {
        VStack(spacing: 8) {
            Image(systemName: "bolt.horizontal.circle").font(.largeTitle).foregroundStyle(.secondary)
            Text("Terminal disconnected").font(.headline)
            Text("""
            Couldn't reach \(host). Make sure Coder Connect is connected (menu bar → \
            Coder Connect), then reopen this tab.
            """)
            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

/// Bridges the non-isolated SwiftTerm process delegate back to SwiftUI. `@MainActor` makes
/// it implicitly Sendable, so the delegate can hop to the main actor to flip `terminated`.
@MainActor
final class TerminalSignal: ObservableObject {
    @Published var terminated = false
}

private struct SSHTerminalView: NSViewRepresentable {
    let host: String
    let signal: TerminalSignal

    func makeCoordinator() -> Coordinator {
        Coordinator(signal: signal)
    }

    @MainActor
    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        view.processDelegate = context.coordinator
        // Match the system text colors so the terminal follows light/dark mode instead of
        // SwiftTerm's near-black default.
        view.configureNativeColors()
        // `-tt` forces a PTY so the remote login shell is interactive; accept the agent's
        // host key on first use (Coder Connect routes to a fresh agent each build).
        view.startProcess(
            executable: "/usr/bin/ssh",
            args: ["-tt", "-o", "StrictHostKeyChecking=accept-new", host]
        )
        return view
    }

    func updateNSView(_: LocalProcessTerminalView, context _: Context) {}

    static func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator _: Coordinator) {
        // Explicitly SIGTERM the ssh child on teardown; relying on PTY hangup at dealloc is
        // non-deterministic and can leave the process lingering (the view is recreated per host
        // via `.id(host)` and destroyed on panel/tab close).
        nsView.terminate()
    }

    /// SwiftTerm's process delegate is non-isolated; we only need to surface termination
    /// (ssh exiting fast usually means the host didn't resolve — Coder Connect is off).
    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        let signal: TerminalSignal

        init(signal: TerminalSignal) {
            self.signal = signal
            super.init()
        }

        func sizeChanged(source _: LocalProcessTerminalView, newCols _: Int, newRows _: Int) {}
        func setTerminalTitle(source _: LocalProcessTerminalView, title _: String) {}
        func hostCurrentDirectoryUpdate(source _: TerminalView, directory _: String?) {}
        func processTerminated(source _: TerminalView, exitCode _: Int32?) {
            let signal = signal
            Task { @MainActor in signal.terminated = true }
        }
    }
}
