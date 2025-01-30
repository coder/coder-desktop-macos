import Testing
@testable import VPNLib

@Suite(.timeLimit(.minutes(1)))
struct ConvertNetworkSettingsTests {
    @Test
    func testConvertDnsSettings() async throws {
        let req: Vpn_NetworkSettingsRequest.DNSSettings = .with { dns in
            dns.servers = ["8.8.8.8"]
            dns.searchDomains = ["example.com"]
            dns.domainName = "example.com"
            dns.matchDomains = ["example.com"]
            dns.matchDomainsNoSearch = false
        }

        let result = convertDnsSettings(req)

        #expect(result.servers == req.servers)
        #expect(result.searchDomains == req.searchDomains)
        #expect(result.domainName == req.domainName)
        #expect(result.matchDomains == req.matchDomains)
        #expect(result.matchDomainsNoSearch == req.matchDomainsNoSearch)
    }

    @Test
    func testConvertIPv4Settings() async throws {
        let req: Vpn_NetworkSettingsRequest.IPv4Settings = .with { ipv4 in
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

        let result = convertIPv4Settings(req)

        #expect(result.addresses == req.addrs)
        #expect(result.subnetMasks == req.subnetMasks)
        #expect(result.router == req.router)

        try #require(result.includedRoutes?.count == req.includedRoutes.count)
        let includedRoute = result.includedRoutes![0]
        let expectedIncludedRoute = req.includedRoutes[0]
        #expect(includedRoute.destinationAddress == expectedIncludedRoute.destination)
        #expect(includedRoute.destinationSubnetMask == expectedIncludedRoute.mask)
        #expect(includedRoute.gatewayAddress == expectedIncludedRoute.router)

        try #require(result.excludedRoutes?.count == req.excludedRoutes.count)
        let excludedRoute = result.excludedRoutes![0]
        let expectedExcludedRoute = req.excludedRoutes[0]
        #expect(excludedRoute.destinationAddress == expectedExcludedRoute.destination)
        #expect(excludedRoute.destinationSubnetMask == expectedExcludedRoute.mask)
        #expect(excludedRoute.gatewayAddress == expectedExcludedRoute.router)
    }

    @Test
    func testConvertIPv6Settings() async throws {
        let req: Vpn_NetworkSettingsRequest.IPv6Settings = .with { ipv6 in
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

        let result = convertIPv6Settings(req)

        #expect(result.addresses == req.addrs)
        #expect(result.networkPrefixLengths == req.prefixLengths.map { NSNumber(value: $0) })

        try #require(result.includedRoutes?.count == req.includedRoutes.count)
        let includedRoute = result.includedRoutes![0]
        let expectedIncludedRoute = req.includedRoutes[0]
        #expect(includedRoute.destinationAddress == expectedIncludedRoute.destination)
        #expect(includedRoute.destinationNetworkPrefixLength == NSNumber(value: 64))
        #expect(includedRoute.gatewayAddress == expectedIncludedRoute.router)

        try #require(result.excludedRoutes?.count == req.excludedRoutes.count)
        let excludedRoute = result.excludedRoutes![0]
        let expectedExcludedRoute = req.excludedRoutes[0]
        #expect(excludedRoute.destinationAddress == expectedExcludedRoute.destination)
        #expect(excludedRoute.destinationNetworkPrefixLength == NSNumber(value: 128))
        #expect(excludedRoute.gatewayAddress == expectedExcludedRoute.router)
    }
}
