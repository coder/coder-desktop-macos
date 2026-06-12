import NetworkExtension
import os

/* From <sys/kern_control.h> */
private let CTLIOCGINFO: UInt = 0xC064_4E03

public extension NEPacketTunnelProvider {
    /// The file descriptor of the utun interface created for this tunnel,
    /// found by scanning for the `utun_control` socket the system opened in
    /// this process. The Go tunnel reads & writes packets on it directly.
    var tunnelFileDescriptor: Int32? {
        var ctlInfo = ctl_info()
        withUnsafeMutablePointer(to: &ctlInfo.ctl_name) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: $0.pointee)) {
                _ = strcpy($0, "com.apple.net.utun_control")
            }
        }
        for fd: Int32 in 0 ... 1024 {
            var addr = sockaddr_ctl()
            var ret: Int32 = -1
            var len = socklen_t(MemoryLayout.size(ofValue: addr))
            withUnsafeMutablePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    ret = getpeername(fd, $0, &len)
                }
            }
            if ret != 0 || addr.sc_family != AF_SYSTEM {
                continue
            }
            if ctlInfo.ctl_id == 0 {
                ret = ioctl(fd, CTLIOCGINFO, &ctlInfo)
                if ret != 0 {
                    continue
                }
            }
            if addr.sc_id == ctlInfo.ctl_id {
                return fd
            }
        }
        return nil
    }
}

public extension NEPacketTunnelNetworkSettings {
    /// Merges a settings diff received from the tunnel into these settings.
    func merge(with diff: Vpn_NetworkSettingsRequest) {
        if diff.hasDnsSettings {
            dnsSettings = convertDnsSettings(diff.dnsSettings)
        }
        if diff.mtu != 0 {
            mtu = NSNumber(value: diff.mtu)
        }
        if diff.hasIpv4Settings {
            ipv4Settings = convertIPv4Settings(diff.ipv4Settings)
        }
        if diff.hasIpv6Settings {
            ipv6Settings = convertIPv6Settings(diff.ipv6Settings)
        }
    }
}
