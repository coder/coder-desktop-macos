@testable import Coder_Desktop
@testable import CoderSDK
import Mocker
import SwiftUI
import Testing
import ViewInspector

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct FilePickerTests {
    let mockResponse: LSResponse

    init() {
        mockResponse = LSResponse(
            absolute_path: ["/"],
            absolute_path_string: "/",
            contents: [
                LSFile(name: "home", absolute_path_string: "/home", is_dir: true),
                LSFile(name: "tmp", absolute_path_string: "/tmp", is_dir: true),
                LSFile(name: "etc", absolute_path_string: "/etc", is_dir: true),
                LSFile(name: "README.md", absolute_path_string: "/README.md", is_dir: false),
            ]
        )
    }

    @Test
    func testLoadError() async throws {
        let host = "test-error.coder"
        let sut = FilePicker(host: host, outputAbsPath: .constant(""))
        let view = sut

        let url = URL(string: "http://\(host):4")!

        let errorMessage = "Connection failed"
        Mock(
            url: url.appendingPathComponent("/api/v0/list-directory"),
            contentType: .json,
            statusCode: 500,
            data: [.post: errorMessage.data(using: .utf8)!]
        ).register()

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                try #expect(await eventually { @MainActor in
                    let text = try view.find(ViewType.Text.self)
                    return try text.string().contains("Connection failed")
                })
            }
        }
    }

    @Test
    func testSuccessfulFileLoad() async throws {
        let host = "test-success.coder"
        let sut = FilePicker(host: host, outputAbsPath: .constant(""))
        let view = sut

        let url = URL(string: "http://\(host):4")!

        try Mock(
            url: url.appendingPathComponent("/api/v0/list-directory"),
            statusCode: 200,
            data: [.post: Client.encoder.encode(mockResponse)]
        ).register()

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                try #expect(await eventually { @MainActor in
                    _ = try view.find(ViewType.List.self)
                    return true
                })
                _ = try view.find(text: "README.md")
                _ = try view.find(text: "home")
                let selectButton = try view.find(button: "Select")
                #expect(selectButton.isDisabled())
            }
        }
    }

    @Test
    func testDirectoryExpansion() async throws {
        let host = "test-expansion.coder"
        let sut = FilePicker(host: host, outputAbsPath: .constant(""))
        let view = sut

        let url = URL(string: "http://\(host):4")!

        try Mock(
            url: url.appendingPathComponent("/api/v0/list-directory"),
            statusCode: 200,
            data: [.post: Client.encoder.encode(mockResponse)]
        ).register()

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                try #expect(await eventually { @MainActor in
                    _ = try view.find(ViewType.List.self)
                    return true
                })

                let disclosureGroup = try view.find(ViewType.DisclosureGroup.self)
                #expect(view.findAll(ViewType.DisclosureGroup.self).count == 3)
                try disclosureGroup.expand()

                // Disclosure group should expand out to 3 more directories
                #expect(await eventually { @MainActor in
                    return view.findAll(ViewType.DisclosureGroup.self).count == 6
                })
            }
        }
    }

    // TODO: The writing of more extensive tests is blocked by ViewInspector,
    // as it can't select an item in a list...
}
