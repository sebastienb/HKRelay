import BridgeCore
import Foundation

public struct HTTPRequest: Sendable {
    public var method: String
    public var path: String
    public var headers: [String: String]
    public var body: Data

    public init(method: String, path: String, headers: [String: String] = [:], body: Data = Data()) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Sendable {
    public var statusCode: Int
    public var reason: String
    public var headers: [String: String]
    public var body: Data
    public static func json(statusCode: Int = 200, envelope: APIEnvelope) -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let body = (try? encoder.encode(envelope)) ?? Data("{\"ok\":false}".utf8)
        return HTTPResponse(
            statusCode: statusCode,
            reason: reasonPhrase(for: statusCode),
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: body
        )
    }

    public static func jsonValue(statusCode: Int = 200, value: JSONValue) -> HTTPResponse {
        HTTPResponse(statusCode: statusCode, reason: reasonPhrase(for: statusCode),
                     headers: ["Content-Type": "application/json; charset=utf-8"],
                     body: (try? JSONEncoder().encode(value)) ?? Data())
    }

    public static func empty(statusCode: Int) -> HTTPResponse {
        HTTPResponse(statusCode: statusCode, reason: reasonPhrase(for: statusCode), headers: [:], body: Data())
    }

    func serialized() -> Data {
        var responseHeaders = headers
        responseHeaders["Content-Length"] = String(body.count)
        responseHeaders["Connection"] = "close"
        responseHeaders["Cache-Control"] = "no-store"

        var head = "HTTP/1.1 \(statusCode) \(reason)\r\n"
        for (name, value) in responseHeaders.sorted(by: { $0.key < $1.key }) {
            head += "\(name): \(value)\r\n"
        }
        head += "\r\n"

        var data = Data(head.utf8)
        data.append(body)
        return data
    }

    private static func reasonPhrase(for statusCode: Int) -> String {
        switch statusCode {
        case 200: "OK"
        case 202: "Accepted"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 406: "Not Acceptable"
        case 415: "Unsupported Media Type"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 413: "Content Too Large"
        case 500: "Internal Server Error"
        case 502: "Bad Gateway"
        case 503: "Service Unavailable"
        default: "Error"
        }
    }
}

enum HTTPParser {
    static let maximumRequestByteCount = 1_048_576
    static let maximumHeaderByteCount = 16_384

    static func parse(_ data: Data) throws -> HTTPRequest? {
        guard data.count <= maximumRequestByteCount else {
            throw HTTPParseError.requestTooLarge
        }

        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator) else {
            guard data.count <= maximumHeaderByteCount else { throw HTTPParseError.invalidHeaders }
            return nil
        }
        guard headerRange.upperBound <= maximumHeaderByteCount else { throw HTTPParseError.invalidHeaders }

        let headerData = data[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            throw HTTPParseError.invalidHeaders
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            throw HTTPParseError.invalidRequestLine
        }
        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard requestParts.count == 3, ["HTTP/1.0", "HTTP/1.1"].contains(String(requestParts[2])),
              requestParts[1].utf8.count <= 2_048, requestParts[1].hasPrefix("/") else {
            throw HTTPParseError.invalidRequestLine
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else {
                throw HTTPParseError.invalidHeaders
            }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else {
                throw HTTPParseError.invalidHeaders
            }
            guard name.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }),
                  value.utf8.allSatisfy({ $0 == 9 || $0 >= 32 && $0 != 127 }) else {
                throw HTTPParseError.invalidHeaders
            }
            if ["content-length", "authorization", "origin", "mcp-protocol-version"].contains(name), headers[name] != nil {
                throw HTTPParseError.invalidHeaders
            }
            headers[name] = value
        }

        guard headers["transfer-encoding"] == nil else {
            throw HTTPParseError.invalidHeaders
        }

        let contentLength: Int
        if let rawContentLength = headers["content-length"] {
            guard let parsedContentLength = Int(rawContentLength), parsedContentLength >= 0 else {
                throw HTTPParseError.invalidHeaders
            }
            contentLength = parsedContentLength
        } else {
            contentLength = 0
        }

        let bodyStart = headerRange.upperBound
        guard contentLength <= maximumRequestByteCount - bodyStart else {
            throw HTTPParseError.requestTooLarge
        }
        guard data.count - bodyStart >= contentLength else {
            return nil
        }

        let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        return HTTPRequest(
            method: String(requestParts[0]).uppercased(),
            path: String(requestParts[1]),
            headers: headers,
            body: body
        )
    }
}

enum HTTPParseError: Error, Equatable {
    case invalidRequestLine
    case invalidHeaders
    case requestTooLarge
}
