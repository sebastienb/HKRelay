import Foundation
import Testing
@testable import BridgeCore

@Test func requestHistoryRedactsQueryStrings() {
    #expect(
        RequestHistorySanitizer.path("/v1/accessories?token=private")
            == "/v1/accessories?[redacted]"
    )
    #expect(RequestHistorySanitizer.path("/health") == "/health")
}

@Test func requestHistoryClassifiesKnownClientsWithoutStoringUserAgent() {
    #expect(RequestHistorySanitizer.client(userAgent: "homekitlink-cli/0.1.0") == .cli)
    #expect(RequestHistorySanitizer.client(userAgent: "hkbridge-cli/0.1.0") == .cli)
    #expect(RequestHistorySanitizer.client(userAgent: "curl/8.7.1") == .curl)
    #expect(RequestHistorySanitizer.client(userAgent: "Mozilla/5.0 private-details") == .browser)
    #expect(RequestHistorySanitizer.client(userAgent: "SecretCustomClient/1.0") == .apiClient)
}

@Test func requestHistoryRedactsSensitiveJSONFields() throws {
    let body = Data(#"{"value":true,"access_token":"private","nested":{"api_key":"private"}}"#.utf8)
    let displayed = try #require(RequestHistorySanitizer.requestBody(body))

    #expect(displayed.contains(#""value" : "[REDACTED]""#))
    #expect(displayed.contains(#""access_token" : "[REDACTED]""#))
    #expect(displayed.contains(#""api_key" : "[REDACTED]""#))
    #expect(!displayed.contains("private"))
}

@Test func requestHistoryOmitsNonJSONBodies() throws {
    let displayed = try #require(RequestHistorySanitizer.requestBody(Data("private text".utf8)))
    #expect(displayed == "[Non-JSON request body omitted: 12 bytes]")
    #expect(!displayed.contains("private text"))
}

@Test func historyRedactsStoredValuesAndDeniedBodies() throws {
    let record = RequestHistoryRecord(method: "POST", path: "/mcp?secret=hidden",
        client: .apiClient, statusCode: 200, durationMilliseconds: 1,
        requestBody: #"{"params":{"arguments":{"value":"1234","pin":"5678","passcode":"9999"}}}"#)
    let sanitized = record.redacted
    #expect(sanitized.id == record.id)
    #expect(!sanitized.path.contains("hidden"))
    let body = try #require(sanitized.requestBody)
    for secret in ["1234", "5678", "9999"] { #expect(!body.contains(secret)) }
    let denied = RequestHistoryRecord(method: "POST", path: "/mcp", client: .apiClient,
        statusCode: 401, durationMilliseconds: 1, requestBody: #"{"anything":"secret"}"#)
    #expect(denied.redacted.requestBody == nil)
    #expect(RequestHistorySanitizer.requestBody(Data(repeating: 65, count: 16_385))
        == "[Large request body omitted: 16385 bytes]")
}
