import BridgeCore
import Foundation
import Testing
@testable import BridgeServer

@Suite("HTTP parser")
struct HTTPParserTests {
    @Test("Parses a complete request")
    func parsesCompleteRequest() throws {
        let data = Data("GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8)

        let parsed = try HTTPParser.parse(data)
        let request = try #require(parsed)

        #expect(request.method == "GET")
        #expect(request.path == "/health")
        #expect(request.headers["host"] == "127.0.0.1")
        #expect(request.body.isEmpty)
    }

    @Test("Waits for a complete body")
    func waitsForCompleteBody() throws {
        let data = Data("PUT /value HTTP/1.1\r\nContent-Length: 5\r\n\r\ntru".utf8)

        #expect(try HTTPParser.parse(data) == nil)
    }

    @Test("Rejects a declared body that exceeds the request limit")
    func rejectsOversizedDeclaredBody() {
        let data = Data("PUT /value HTTP/1.1\r\nContent-Length: \(Int.max)\r\n\r\n".utf8)

        #expect(throws: HTTPParseError.requestTooLarge) {
            try HTTPParser.parse(data)
        }
    }

    @Test("Rejects malformed content length")
    func rejectsMalformedContentLength() {
        let data = Data("PUT /value HTTP/1.1\r\nContent-Length: invalid\r\n\r\n".utf8)

        #expect(throws: HTTPParseError.invalidHeaders) {
            try HTTPParser.parse(data)
        }
    }

    @Test("Rejects duplicate content length")
    func rejectsDuplicateContentLength() {
        let data = Data("PUT /value HTTP/1.1\r\nContent-Length: 0\r\nContent-Length: 1\r\n\r\n".utf8)

        #expect(throws: HTTPParseError.invalidHeaders) {
            try HTTPParser.parse(data)
        }
    }

    @Test("Rejects unsupported transfer encoding")
    func rejectsTransferEncoding() {
        let data = Data("PUT /value HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n".utf8)

        #expect(throws: HTTPParseError.invalidHeaders) {
            try HTTPParser.parse(data)
        }
    }
    @Test("Rejects oversized headers and request targets")
    func headerAndTargetLimits() {
        for text in [
            "GET / HTTP/1.1\r\nX-Padding: " + String(repeating: "a", count: 17_000),
            "GET /" + String(repeating: "a", count: 2_049) + " HTTP/1.1\r\n\r\n"
        ] {
            #expect(throws: (any Error).self) { try HTTPParser.parse(Data(text.utf8)) }
        }
    }

    @Test("Rejects control bytes, whitespace in header names, and invalid HTTP versions")
    func strictHeaders() {
        for text in [
            "GET / HTTP/1.1\r\nAuthorization: Bearer mock\0token\r\n\r\n",
            "GET / HTTP/1.1\r\nBad Name: value\r\n\r\n",
            "GET / HTTP/1.99\r\n\r\n"
        ] {
            #expect(throws: (any Error).self) { try HTTPParser.parse(Data(text.utf8)) }
        }
    }

}
