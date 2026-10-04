import BridgeCore
import BridgeServer
import Foundation
import Observation

@MainActor
@Observable
final class RequestHistoryStore {
    static let internalRequestHeader = "x-homekit-bridge-internal"
    static let menuBarHealthValue = "menu-bar-health"
    static let menuBarHealthPath = "/_internal/menu-bar-health"
    private static let loggingEnabledKey = "requestHistory.loggingEnabled"

    private(set) var records: [RequestHistoryRecord] = []
    private(set) var persistenceIssue: String?
    var isLoggingEnabled: Bool {
        didSet {
            defaults.set(isLoggingEnabled, forKey: Self.loggingEnabledKey)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let fileManager: FileManager
    @ObservationIgnored private let historyURL: URL
    @ObservationIgnored private let maximumRecordCount = 500

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        isLoggingEnabled = defaults.object(forKey: Self.loggingEnabledKey) == nil
            ? true
            : defaults.bool(forKey: Self.loggingEnabledKey)

        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        historyURL = applicationSupport
            .appendingPathComponent("HomeKitRESTBridge", isDirectory: true)
            .appendingPathComponent("request-history.json", isDirectory: false)

        load()
    }

    func record(
        request: HTTPRequest,
        response: HTTPResponse,
        duration: TimeInterval
    ) {
        guard isLoggingEnabled else { return }
        guard request.path != Self.menuBarHealthPath else { return }

        let record = RequestHistoryRecord(
            method: request.method,
            path: RequestHistorySanitizer.path(request.path),
            client: RequestHistorySanitizer.client(userAgent: request.headers["user-agent"]),
            statusCode: response.statusCode,
            durationMilliseconds: Int(max(0, duration) * 1_000),
            requestBody: [401, 403].contains(response.statusCode) ? nil : RequestHistorySanitizer.requestBody(request.body)
        )

        records.insert(record, at: 0)
        if records.count > maximumRecordCount {
            records.removeLast(records.count - maximumRecordCount)
        }
        persist()
    }

    func clear() {
        records.removeAll()
        persist()
    }

    private func load() {
        guard fileManager.fileExists(atPath: historyURL.path) else { return }

        do {
            let data = try Data(contentsOf: historyURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            records = Array(try decoder.decode([RequestHistoryRecord].self, from: data).prefix(maximumRecordCount)).map(\.redacted)
            persist()
        } catch {
            persistenceIssue = "Saved history could not be loaded. New requests will still appear here."
        }
    }

    private func persist() {
        do {
            let directoryURL = historyURL.deletingLastPathComponent()
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            try PrivateFile.write(encoder.encode(records), to: historyURL)
            persistenceIssue = nil
        } catch {
            persistenceIssue = "History is visible for this session but could not be saved."
        }
    }
}
