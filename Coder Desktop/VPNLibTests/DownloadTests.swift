import Foundation
import Mocker
import Testing
@testable import VPNLib

@Suite(.timeLimit(.minutes(1)))
struct DownloadTests {
    @Test
    func downloadFile() async throws {
        let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let testData = Data("foo".utf8)

        let fileURL = URL(string: "http://example.com/test1.txt")!
        Mock(url: fileURL, contentType: .html, statusCode: 200, data: [.get: testData]).register()

        try await download(src: fileURL, dest: destinationURL)

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

        try await download(src: fileURL, dest: destinationURL)
        try #require(FileManager.default.fileExists(atPath: destinationURL.path))
        let downloadedData = try Data(contentsOf: destinationURL)
        #expect(downloadedData == testData)

        var mock = Mock(url: fileURL, contentType: .html, statusCode: 304, data: [.get: Data()])
        var etagIncluded = false
        mock.onRequestHandler = OnRequestHandler { request in
            etagIncluded = request.value(forHTTPHeaderField: "If-None-Match") == etag(data: testData)
        }
        mock.register()

        try await download(src: fileURL, dest: destinationURL)
        let unchangedData = try Data(contentsOf: destinationURL)
        #expect(unchangedData == testData)
        #expect(etagIncluded)
    }

    @Test
    func fileUpdated() async throws {
        let ogData = Data("foo bar".utf8)
        let newData = Data("foo bar qux".utf8)

        let fileURL = URL(string: "http://example.com/test3.txt")!
        let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: destinationURL) }

        Mock(url: fileURL, contentType: .html, statusCode: 200, data: [.get: ogData]).register()

        try await download(src: fileURL, dest: destinationURL)
        try #require(FileManager.default.fileExists(atPath: destinationURL.path))
        var downloadedData = try Data(contentsOf: destinationURL)
        #expect(downloadedData == ogData)

        var mock = Mock(url: fileURL, contentType: .html, statusCode: 200, data: [.get: newData])
        var etagIncluded = false
        mock.onRequestHandler = OnRequestHandler { request in
            etagIncluded = request.value(forHTTPHeaderField: "If-None-Match") == etag(data: ogData)
        }
        mock.register()

        try await download(src: fileURL, dest: destinationURL)
        downloadedData = try Data(contentsOf: destinationURL)
        #expect(downloadedData == newData)
        #expect(etagIncluded)
    }
}
