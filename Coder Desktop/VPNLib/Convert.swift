import NetworkExtension
import os

// swiftlint:disable function_body_length
public func convertNetworkSettingsRequest(_ req: Vpn_NetworkSettingsRequest) -> NEPacketTunnelNetworkSettings {
    let networkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: req.tunnelRemoteAddress)
    networkSettings.tunnelOverheadBytes = NSNumber(value: req.tunnelOverheadBytes)
    networkSettings.mtu = NSNumber(value: req.mtu)

    if req.hasDnsSettings {
        let dnsSettings = NEDNSSettings(servers: req.dnsSettings.servers)
        dnsSettings.searchDomains = req.dnsSettings.searchDomains
        dnsSettings.domainName = req.dnsSettings.domainName
        dnsSettings.matchDomains = req.dnsSettings.matchDomains
        dnsSettings.matchDomainsNoSearch = req.dnsSettings.matchDomainsNoSearch
        networkSettings.dnsSettings = dnsSettings
    }

    if req.hasIpv4Settings {
        let ipv4Settings = NEIPv4Settings(addresses: req.ipv4Settings.addrs, subnetMasks: req.ipv4Settings.subnetMasks)
        ipv4Settings.router = req.ipv4Settings.router
        ipv4Settings.includedRoutes = req.ipv4Settings.includedRoutes.map {
            let route = NEIPv4Route(destinationAddress: $0.destination, subnetMask: $0.mask)
            route.gatewayAddress = $0.router
            return route
        }
        ipv4Settings.excludedRoutes = req.ipv4Settings.excludedRoutes.map {
            let route = NEIPv4Route(destinationAddress: $0.destination, subnetMask: $0.mask)
            route.gatewayAddress = $0.router
            return route
        }
        networkSettings.ipv4Settings = ipv4Settings
    }

    if req.hasIpv6Settings {
        let ipv6Settings = NEIPv6Settings(
            addresses: req.ipv6Settings.addrs,
            networkPrefixLengths: req.ipv6Settings.prefixLengths.map { NSNumber(value: $0)
            }
        )
        ipv6Settings.includedRoutes = req.ipv6Settings.includedRoutes.map {
            let route = NEIPv6Route(
                destinationAddress: $0.destination,
                networkPrefixLength: NSNumber(value: $0.prefixLength)
            )
            route.gatewayAddress = $0.router
            return route
        }
        ipv6Settings.excludedRoutes = req.ipv6Settings.excludedRoutes.map {
            let route = NEIPv6Route(
                destinationAddress: $0.destination,
                networkPrefixLength: NSNumber(value: $0.prefixLength)
            )
            route.gatewayAddress = $0.router
            return route
        }
        networkSettings.ipv6Settings = ipv6Settings
    }
    return networkSettings
}
