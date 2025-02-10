import NetworkExtension
import os
import SwiftProtobuf

public func convertDnsSettings(_ req: Vpn_NetworkSettingsRequest.DNSSettings) -> NEDNSSettings {
    let dnsSettings = NEDNSSettings(servers: req.servers)
    dnsSettings.searchDomains = req.searchDomains
    dnsSettings.domainName = req.domainName
    dnsSettings.matchDomains = req.matchDomains
    dnsSettings.matchDomainsNoSearch = req.matchDomainsNoSearch
    return dnsSettings
}

public func convertIPv4Settings(_ req: Vpn_NetworkSettingsRequest.IPv4Settings) -> NEIPv4Settings {
    let ipv4Settings = NEIPv4Settings(addresses: req.addrs, subnetMasks: req.subnetMasks)
    if !req.router.isEmpty {
        ipv4Settings.router = req.router
    }
    ipv4Settings.includedRoutes = req.includedRoutes.map {
        let route = NEIPv4Route(destinationAddress: $0.destination, subnetMask: $0.mask)
        if !$0.router.isEmpty {
            route.gatewayAddress = $0.router
        }
        return route
    }
    ipv4Settings.excludedRoutes = req.excludedRoutes.map {
        let route = NEIPv4Route(destinationAddress: $0.destination, subnetMask: $0.mask)
        if !$0.router.isEmpty {
            route.gatewayAddress = $0.router
        }
        return route
    }
    return ipv4Settings
}

public func convertIPv6Settings(_ req: Vpn_NetworkSettingsRequest.IPv6Settings) -> NEIPv6Settings {
    let ipv6Settings = NEIPv6Settings(
        addresses: req.addrs,
        networkPrefixLengths: req.prefixLengths.map { NSNumber(value: $0) }
    )
    ipv6Settings.includedRoutes = req.includedRoutes.map {
        let route = NEIPv6Route(
            destinationAddress: $0.destination,
            networkPrefixLength: NSNumber(value: $0.prefixLength)
        )
        if !$0.router.isEmpty {
            route.gatewayAddress = $0.router
        }
        return route
    }
    ipv6Settings.excludedRoutes = req.excludedRoutes.map {
        let route = NEIPv6Route(
            destinationAddress: $0.destination,
            networkPrefixLength: NSNumber(value: $0.prefixLength)
        )
        if !$0.router.isEmpty {
            route.gatewayAddress = $0.router
        }
        return route
    }
    return ipv6Settings
}

extension Google_Protobuf_Timestamp {
    var date: Date {
        let seconds = TimeInterval(seconds)
        let nanos = TimeInterval(nanos) / 1_000_000_000
        return Date(timeIntervalSince1970: seconds + nanos)
    }
}
