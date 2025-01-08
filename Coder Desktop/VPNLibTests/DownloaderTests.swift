import Foundation
import Mocker
import Testing
@testable import VPNLib

struct NoopValidator: Validator {
    func validate(path _: URL) async throws {}
}

@Suite
struct DownloaderTests {
    let downloader = Downloader(validator: NoopValidator())

    @Test
    func downloadFile() async throws {
        let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let testData = Data("foo".utf8)

        let fileURL = URL(string: "http://example.com/test1.txt")!
        Mock(url: fileURL, contentType: .html, statusCode: 200, data: [.get: testData]).register()

        try await downloader.download(src: fileURL, dest: destinationURL)

        try #require(FileManager.default.fileExists(atPath: destinationURL.path))
        defer { try? FileManager.default.removeItem(at: destinationURL) }

        let downloadedData = try Data(contentsOf: destinationURL)
        #expect(downloadedData == testData)
    }

    @Test
    func fileNotModified() async throws {
        let testData = Data("foo bar".utf8)
        let fileURL = URL(string: "http://example.com/test2.txt")!

        let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: destinationURL) }

        Mock(url: fileURL, contentType: .html, statusCode: 200, data: [.get: testData]).register()

        try await downloader.download(src: fileURL, dest: destinationURL)
        try #require(FileManager.default.fileExists(atPath: destinationURL.path))
        let downloadedData = try Data(contentsOf: destinationURL)
        #expect(downloadedData == testData)

        Mock(url: fileURL, contentType: .html, statusCode: 304, data: [.get: Data()]).register()

        try await downloader.download(src: fileURL, dest: destinationURL)
        let unchangedData = try Data(contentsOf: destinationURL)
        #expect(unchangedData == testData)
    }

    @Test
    func fileUpdated() async throws {
        let ogData = Data("foo bar".utf8)
        let newData = Data("foo bar qux".utf8)

        let fileURL = URL(string: "http://example.com/test3.txt")!
        let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: destinationURL) }

        Mock(url: fileURL, contentType: .html, statusCode: 200, data: [.get: ogData]).register()

        try await downloader.download(src: fileURL, dest: destinationURL)
        try #require(FileManager.default.fileExists(atPath: destinationURL.path))
        var downloadedData = try Data(contentsOf: destinationURL)
        #expect(downloadedData == ogData)

        Mock(url: fileURL, contentType: .html, statusCode: 200, data: [.get: newData]).register()

        try await downloader.download(src: fileURL, dest: destinationURL)
        downloadedData = try Data(contentsOf: destinationURL)
        #expect(downloadedData == newData)
    }
}
