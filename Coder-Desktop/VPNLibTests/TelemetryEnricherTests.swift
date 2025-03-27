import Testing
@testable import VPNLib

@Suite(.timeLimit(.minutes(1)))
struct TelemetryEnricherTests {
    @Test func testEnrichStartRequest() throws {
        let enricher0 = TelemetryEnricher()
        let original = Vpn_StartRequest.with { req in
            req.coderURL = "https://example.com"
            req.tunnelFileDescriptor = 123
        }
        var enriched = enricher0.enrich(original)
        #expect(enriched.coderURL == "https://example.com")
        #expect(enriched.tunnelFileDescriptor == 123)
        #expect(enriched.deviceOs == "macOS")
        #expect(try enriched.coderDesktopVersion.contains(Regex(#"^\d+\.\d+\.\d+$"#)))
        let deviceID = enriched.deviceID
        #expect(!deviceID.isEmpty)

        // check we get the same deviceID from a new enricher
        let enricher1 = TelemetryEnricher()
        enriched = enricher1.enrich(original)
        #expect(enriched.deviceID == deviceID)
    }
}
