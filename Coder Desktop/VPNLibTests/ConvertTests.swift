import Testing
@testable import VPNLib

@Suite(.timeLimit(.minutes(1)))
struct ConvertTests {
    @Test
    // swiftlint:disable:next function_body_length
    func convertProtoNetworkSettingsRequest() async throws {
        let req: Vpn_NetworkSettingsRequest = .with { req in
            req.tunnelRemoteAddress = "10.0.0.1"
            req.tunnelOverheadBytes = 20
            req.mtu = 1400

            req.dnsSettings = .with { dns in
                dns.servers = ["8.8.8.8"]
                dns.searchDomains = ["example.com"]
                dns.domainName = "example.com"
                dns.matchDomains = ["example.com"]
                dns.matchDomainsNoSearch = false
            }

            req.ipv4Settings = .with { ipv4 in
                ipv4.addrs = ["192.168.1.1"]
                ipv4.subnetMasks = ["255.255.255.0"]
                ipv4.router = "192.168.1.254"
                ipv4.includedRoutes = [
                    .with { route in
                        route.destination = "10.0.0.0"
                        route.mask = "255.0.0.0"
                        route.router = "192.168.1.254"
                    },
                ]
                ipv4.excludedRoutes = [
                    .with { route in
                        route.destination = "172.16.0.0"
                        route.mask = "255.240.0.0"
                        route.router = "192.168.1.254"
                    },
                ]
            }

            req.ipv6Settings = .with { ipv6 in
                ipv6.addrs = ["2001:db8::1"]
                ipv6.prefixLengths = [64]
                ipv6.includedRoutes = [
                    .with { route in
                        route.destination = "2001:db8::"
                        route.router = "2001:db8::1"
                        route.prefixLength = 64
                    },
                ]
                ipv6.excludedRoutes = [
                    .with { route in
                        route.destination = "2001:0db8:85a3::"
                        route.router = "2001:db8::1"
                        route.prefixLength = 128
                    },
                ]
            }
        }

        let result = convertNetworkSettingsRequest(req)
        #expect(result.tunnelRemoteAddress == req.tunnelRemoteAddress)
        #expect(result.dnsSettings!.servers == req.dnsSettings.servers)
        #expect(result.dnsSettings!.domainName == req.dnsSettings.domainName)
        #expect(result.ipv4Settings!.addresses == req.ipv4Settings.addrs)
        #expect(result.ipv4Settings!.subnetMasks == req.ipv4Settings.subnetMasks)
        #expect(result.ipv6Settings!.addresses == req.ipv6Settings.addrs)
        #expect(result.ipv6Settings!.networkPrefixLengths == [64])

        try #require(result.ipv4Settings!.includedRoutes?.count == req.ipv4Settings.includedRoutes.count)
        let ipv4IncludedRoute = result.ipv4Settings!.includedRoutes![0]
        let expectedIpv4IncludedRoute = req.ipv4Settings.includedRoutes[0]
        #expect(ipv4IncludedRoute.destinationAddress == expectedIpv4IncludedRoute.destination)
        #expect(ipv4IncludedRoute.destinationSubnetMask == expectedIpv4IncludedRoute.mask)
        #expect(ipv4IncludedRoute.gatewayAddress == expectedIpv4IncludedRoute.router)

        try #require(result.ipv4Settings!.excludedRoutes?.count == req.ipv4Settings.excludedRoutes.count)
        let ipv4ExcludedRoute = result.ipv4Settings!.excludedRoutes![0]
        let expectedIpv4ExcludedRoute = req.ipv4Settings.excludedRoutes[0]
        #expect(ipv4ExcludedRoute.destinationAddress == expectedIpv4ExcludedRoute.destination)
        #expect(ipv4ExcludedRoute.destinationSubnetMask == expectedIpv4ExcludedRoute.mask)
        #expect(ipv4ExcludedRoute.gatewayAddress == expectedIpv4ExcludedRoute.router)

        try #require(result.ipv6Settings!.includedRoutes?.count == req.ipv6Settings.includedRoutes.count)
        let ipv6IncludedRoute = result.ipv6Settings!.includedRoutes![0]
        let expectedIpv6IncludedRoute = req.ipv6Settings.includedRoutes[0]
        #expect(ipv6IncludedRoute.destinationAddress == expectedIpv6IncludedRoute.destination)
        #expect(ipv6IncludedRoute.destinationNetworkPrefixLength == 64)
        #expect(ipv6IncludedRoute.gatewayAddress == expectedIpv6IncludedRoute.router)

        try #require(result.ipv6Settings!.excludedRoutes?.count == req.ipv6Settings.excludedRoutes.count)
        let ipv6ExcludedRoute = result.ipv6Settings!.excludedRoutes![0]
        let expectedIpv6ExcludedRoute = req.ipv6Settings.excludedRoutes[0]
        #expect(ipv6ExcludedRoute.destinationAddress == expectedIpv6ExcludedRoute.destination)
        #expect(ipv6ExcludedRoute.destinationNetworkPrefixLength == 128)
        #expect(ipv6ExcludedRoute.gatewayAddress == expectedIpv6ExcludedRoute.router)
    }
}
