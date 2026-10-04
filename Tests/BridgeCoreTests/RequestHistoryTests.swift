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
    #expect(RequestHistorySanitizer.client(userAgent: "hkbridge-cli/0.1.0") == .cli)
    #expect(RequestHistorySanitizer.client(userAgent: "curl/8.7.1") == .curl)
    #expect(RequestHistorySanitizer.client(userAgent: "Mozilla/5.0 private-details") == .browser)
    #expect(RequestHistorySanitizer.client(userAgent: "SecretCustomClient/1.0") == .apiClient)
}

@Test func requestHistoryRedactsSensitiveJSONFields() throws {
    let body = Data(#"{"value":true,"access_token":"private","nested":{"api_key":"private"}}"#.utf8)
    let displayed = try #require(RequestHistorySanitizer.requestBody(body))

    #expect(displayed.contains(#""value" : true"#))
    #expect(displayed.contains(#""access_token" : "[REDACTED]""#))
    #expect(displayed.contains(#""api_key" : "[REDACTED]""#))
    #expect(!displayed.contains("private"))
}

@Test func requestHistoryOmitsNonJSONBodies() throws {
    let displayed = try #require(RequestHistorySanitizer.requestBody(Data("private text".utf8)))
    #expect(displayed == "[Non-JSON request body omitted: 12 bytes]")
    #expect(!displayed.contains("private text"))
}
