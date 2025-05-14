import LaunchAtLogin
import ServiceManagement
import SwiftUI

struct HelperSection: View {
    var body: some View {
        Section {
            HelperButton()
            Text("""
            Coder Connect executes a dynamic library downloaded from the Coder deployment.
            Administrator privileges are required when executing a copy of this library for the first time.
            Without this helper, these are granted by the user entering their password.
            With this helper, this is done automatically.
            This is useful if the Coder deployment updates frequently.

            Coder Desktop will not execute code unless it has been signed by Coder.
            """)
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
    }
}

struct HelperButton: View {
    @EnvironmentObject var helperService: HelperService

    var buttonText: String {
        switch helperService.state {
        case .uninstalled, .failed:
            "Install"
        case .installed:
            "Uninstall"
        case .requiresApproval:
            "Open Settings"
        }
    }

    var buttonDescription: String {
        switch helperService.state {
        case .uninstalled, .installed:
            ""
        case .requiresApproval:
            "Requires approval"
        case let .failed(err):
            err.localizedDescription
        }
    }

    func buttonAction() {
        switch helperService.state {
        case .uninstalled, .failed:
            helperService.install()
            if helperService.state == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        case .installed:
            helperService.uninstall()
        case .requiresApproval:
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    var body: some View {
        HStack {
            Text("Privileged Helper")
            Spacer()
            Text(buttonDescription)
                .foregroundColor(.secondary)
            Button(action: buttonAction) {
                Text(buttonText)
            }
        }.onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            helperService.update()
        }.onAppear {
            helperService.update()
        }
    }
}

#Preview {
    HelperSection().environmentObject(HelperService())
}
