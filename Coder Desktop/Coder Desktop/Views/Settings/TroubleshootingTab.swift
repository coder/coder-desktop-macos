import SwiftUI

struct TroubleshootingTab<VPN: VPNService>: View {
    @EnvironmentObject private var vpn: VPN
    @State private var isProcessing = false
    @State private var showUninstallAlert = false
    @State private var showToggleAlert = false
    @State private var systemExtensionError: String?
    @State private var networkExtensionError: String?

    var body: some View {
        Form {
            Section(header: Text("System Extension")) {
                // Only show install/uninstall buttons here
                installOrUninstallButton

                if let error = systemExtensionError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }

                // Display current extension status
                HStack {
                    Text("Status:")
                    Spacer()
                    statusView
                }
            }

            Section(
                header: Text("VPN Configuration"),
                footer: Text("These options are for troubleshooting only. Do not modify unless instructed by support.")
            ) {
                // Show enable/disable button here
                if case .installed = vpn.sysExtnState {
                    enableOrDisableButton

                    if let error = networkExtensionError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }

                // Display network extension status
                HStack {
                    Text("Network Extension:")
                    Spacer()
                    networkStatusView
                }
            }
        }.formStyle(.grouped)
    }

    @ViewBuilder
    private var statusView: some View {
        switch vpn.sysExtnState {
        case .installed:
            Text("Installed")
                .foregroundColor(.green)
        case .uninstalled:
            Text("Not Installed")
                .foregroundColor(.secondary)
        case .needsUserApproval:
            Text("Needs Approval")
                .foregroundColor(.orange)
        case let .failed(message):
            Text("Failed: \(message)")
                .foregroundColor(.red)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var networkStatusView: some View {
        switch vpn.neState {
        case .enabled:
            Text("Enabled")
                .foregroundColor(.green)
        case .disabled:
            Text("Disabled")
                .foregroundColor(.orange)
        case .unconfigured:
            Text("Not Configured")
                .foregroundColor(.secondary)
        case let .failed(message):
            Text("Failed: \(message)")
                .foregroundColor(.red)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var installOrUninstallButton: some View {
        if case .installed = vpn.sysExtnState {
            // Uninstall button
            Button {
                showUninstallAlert = true
            } label: {
                HStack {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.red)
                    Text("Uninstall Network Extension")
                    Spacer()
                    if isProcessing, showUninstallAlert {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(isProcessing)
            .alert(isPresented: $showUninstallAlert) {
                Alert(
                    title: Text("Uninstall Network Extension"),
                    message: Text("This will completely uninstall the VPN system extension. " +
                        "You will need to reinstall it to use the VPN again."),
                    primaryButton: .destructive(Text("Uninstall")) {
                        performUninstall()
                    },
                    secondaryButton: .cancel()
                )
            }
        } else {
            // Show install button when extension is not installed
            Button {
                performInstall()
            } label: {
                HStack {
                    Image(systemName: "arrow.down.circle")
                        .foregroundColor(.blue)
                    Text("Install Network Extension")
                    Spacer()
                    if isProcessing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(isProcessing)
        }
    }

    @ViewBuilder
    private var enableOrDisableButton: some View {
        Button {
            showToggleAlert = true
        } label: {
            HStack {
                Image(systemName: vpn.neState == .enabled ? "pause.circle" : "play.circle")
                    .foregroundColor(vpn.neState == .enabled ? .orange : .green)
                Text(vpn.neState == .enabled ? "Remove VPN Configuration" : "Enable VPN Configuration")
                Spacer()
                if isProcessing, showToggleAlert {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .disabled(isProcessing)
        .alert(isPresented: $showToggleAlert) {
            if vpn.neState == .enabled {
                Alert(
                    title: Text("Remove VPN Configuration"),
                    message: Text("This will stop the VPN service but keep the system extension " +
                        "installed. You can enable it again later."),
                    primaryButton: .default(Text("Remove")) {
                        performDisable()
                    },
                    secondaryButton: .cancel()
                )
            } else {
                Alert(
                    title: Text("Enable VPN Configuration"),
                    message: Text("This will enable the network extension to allow VPN connections."),
                    primaryButton: .default(Text("Enable")) {
                        performEnable()
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    private func performUninstall() {
        isProcessing = true
        systemExtensionError = nil
        networkExtensionError = nil

        Task {
            let success = await vpn.uninstall()
            isProcessing = false

            if !success {
                systemExtensionError = "Failed to uninstall network extension. Check logs for details."
            }
        }
    }

    private func performInstall() {
        isProcessing = true
        systemExtensionError = nil
        networkExtensionError = nil

        Task {
            await vpn.installExtension()
            isProcessing = false

            // Check if installation failed
            if case let .failed(message) = vpn.sysExtnState {
                systemExtensionError = "Failed to install: \(message)"
            }
        }
    }

    private func performDisable() {
        isProcessing = true
        systemExtensionError = nil
        networkExtensionError = nil

        Task {
            let success = await vpn.disableExtension()
            isProcessing = false

            if !success {
                networkExtensionError = "Failed to disable network extension. Check logs for details."
            }
        }
    }

    private func performEnable() {
        isProcessing = true
        systemExtensionError = nil
        networkExtensionError = nil

        Task {
            let initialState = vpn.neState
            let success = await vpn.enableExtension()
            isProcessing = false

            // Only show error if we failed AND the state didn't change
            // This handles the case where enableExtension returns false but the configuration
            // was successfully applied (unchanged configuration returns false on macOS)
            if !success, vpn.neState == initialState, vpn.neState != .enabled {
                networkExtensionError = "Failed to enable network extension. Check logs for details."
            }
        }
    }
}

#Preview("Extension Installed") {
    TroubleshootingTab<PreviewVPN>()
        .environmentObject(AppState())
        .environmentObject(PreviewVPN(extensionInstalled: true, networkExtensionEnabled: true))
}

#Preview("Extension Installed, NE Disabled") {
    TroubleshootingTab<PreviewVPN>()
        .environmentObject(AppState())
        .environmentObject(PreviewVPN(extensionInstalled: true, networkExtensionEnabled: false))
}

#Preview("Extension Not Installed") {
    TroubleshootingTab<PreviewVPN>()
        .environmentObject(AppState())
        .environmentObject(PreviewVPN(extensionInstalled: false))
}

#Preview("Extension Failed") {
    TroubleshootingTab<PreviewVPN>()
        .environmentObject(AppState())
        .environmentObject(PreviewVPN(shouldFail: true))
}
