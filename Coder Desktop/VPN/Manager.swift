import NetworkExtension
import os
import VPNLib

actor Manager {
    let ptp: PacketTunnelProvider
    let downloader: Downloader

    var tunnelHandle: TunnelHandle?
    var speaker: Speaker<Vpn_TunnelMessage, Vpn_ManagerMessage>?
    // TODO: XPC Speaker

    private let dest = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        .first!.appending(path: "coder-vpn.dylib")

    init(with: PacketTunnelProvider) {
        ptp = with
        downloader = Downloader()
    }
}
