import Foundation
import Swifter
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

        let server = HttpServer()
        let testData = Data("foo".utf8)

        server["/test.txt"] = { _ in
            HttpResponse.ok(.data(testData))
        }

        try server.start(freePort())
        defer { server.stop() }

        let fileURL = try URL(string: "http://localhost:\(server.port())/test.txt")!
        try await downloader.download(src: fileURL, dest: destinationURL)

        try #require(FileManager.default.fileExists(atPath: destinationURL.path))
        defer { try? FileManager.default.removeItem(at: destinationURL) }

        let downloadedData = try Data(contentsOf: destinationURL)
        #expect(downloadedData == testData)
    }

    @Test
    func fileNotModified() async throws {
        let server = HttpServer()
        let testData = Data("foo bar".utf8)

        let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        var notModifiedSent = false
        server["/test.txt"] = { req in
            let etag = etag(data: testData)
            if let ifNoneMatch = req.headers["if-none-match"], ifNoneMatch == etag {
                notModifiedSent = true
                return .raw(304, "Not Modified", nil, nil)
            } else {
                return .ok(.data(testData))
            }
        }

        try server.start(freePort())
        defer { server.stop() }

        let fileURL = try URL(string: "http://localhost:\(server.port())/test.txt")!
        try await downloader.download(src: fileURL, dest: destinationURL)

        try #require(FileManager.default.fileExists(atPath: destinationURL.path))
        defer { try? FileManager.default.removeItem(at: destinationURL) }
        let downloadedData = try Data(contentsOf: destinationURL)
        #expect(downloadedData == testData)

        try await downloader.download(src: fileURL, dest: destinationURL)
        #expect(downloadedData == testData)
        #expect(notModifiedSent)
    }

    @Test
    func fileUpdated() async throws {
        let server = HttpServer()
        let ogData = Data("foo bar".utf8)
        let newData = Data("foo bar qux".utf8)

        let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        server["/test.txt"] = { _ in
            .ok(.data(ogData))
        }

        try server.start(freePort())
        defer { server.stop() }

        let fileURL = try URL(string: "http://localhost:\(server.port())/test.txt")!

        try await downloader.download(src: fileURL, dest: destinationURL)
        try #require(FileManager.default.fileExists(atPath: destinationURL.path))
        defer { try? FileManager.default.removeItem(at: destinationURL) }
        var downloadedData = try Data(contentsOf: destinationURL)
        #expect(downloadedData == ogData)

        server["/test.txt"] = { _ in
            .ok(.data(newData))
        }
        try await downloader.download(src: fileURL, dest: destinationURL)
        downloadedData = try Data(contentsOf: destinationURL)
        #expect(downloadedData == newData)
    }
}

// From https://stackoverflow.com/questions/65670932/how-to-find-a-free-local-port-using-swift
func freePort() -> UInt16 {
    var port: UInt16 = 8000

    let socketFD = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    if socketFD == -1 {
        return port
    }

    var hints = addrinfo(
        ai_flags: AI_PASSIVE,
        ai_family: AF_INET,
        ai_socktype: SOCK_STREAM,
        ai_protocol: 0,
        ai_addrlen: 0,
        ai_canonname: nil,
        ai_addr: nil,
        ai_next: nil
    )

    var addressInfo: UnsafeMutablePointer<addrinfo>?
    var result = getaddrinfo(nil, "0", &hints, &addressInfo)
    if result != 0 {
        close(socketFD)
        return port
    }

    result = Darwin.bind(socketFD, addressInfo!.pointee.ai_addr, socklen_t(addressInfo!.pointee.ai_addrlen))
    if result == -1 {
        close(socketFD)
        return port
    }

    result = Darwin.listen(socketFD, 1)
    if result == -1 {
        close(socketFD)
        return port
    }

    var addr_in = sockaddr_in()
    addr_in.sin_len = UInt8(MemoryLayout.size(ofValue: addr_in))
    addr_in.sin_family = sa_family_t(AF_INET)

    var len = socklen_t(addr_in.sin_len)
    result = withUnsafeMutablePointer(to: &addr_in) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.getsockname(socketFD, $0, &len)
        }
    }

    if result == 0 {
        port = addr_in.sin_port
    }

    Darwin.shutdown(socketFD, SHUT_RDWR)
    close(socketFD)

    return port
}
