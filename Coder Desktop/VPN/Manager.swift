import NetworkExtension
import os
import VPNLib

actor Manager {
    let ptp: PacketTunnelProvider

    var tunnelHandle: TunnelHandle?
    var speaker: Speaker<Vpn_ManagerMessage, Vpn_TunnelMessage>?
    // TODO: XPC Speaker

    private let dest = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        .first!.appending(path: "coder-vpn.dylib")
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "manager")

    init(with: PacketTunnelProvider) {
        ptp = with
    }
}
