import NetworkExtension
import os
import VPNLib

actor Manager {
    let ptp: PacketTunnelProvider
    let downloader: Downloader

    var tunnelHandle: TunnelHandle?
    var speaker: Speaker<Vpn_ManagerMessage, Vpn_TunnelMessage>?
    // TODO: XPC Speaker

    private let dest = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        .first!.appending(path: "coder-vpn.dylib")
    private let logger = Logger(subsystem: "com.coder.Coder.CoderPacketTunnelProvider", category: "manager")

    init(with: PacketTunnelProvider) {
        ptp = with
        downloader = Downloader()
    }
}
