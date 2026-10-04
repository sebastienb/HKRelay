import OSLog
import ServiceManagement

@MainActor
final class MenuBarHelperController {
    static let shared = MenuBarHelperController()

    private let logger = Logger(
        subsystem: "org.homekitrestbridge.app",
        category: "MenuBarHelper"
    )

    private init() {}

    @discardableResult
    func start() throws -> Bool {
        let service = try service()
        switch service.status {
        case .enabled:
            logger.notice("Menu bar helper is registered.")
            return false
        case .notRegistered, .notFound:
            try service.register()
            logger.notice("Menu bar helper was registered.")
            return service.status == .requiresApproval
        case .requiresApproval:
            return true
        @unknown default:
            throw MenuBarHelperError.unknownStatus
        }
    }

    func stop() throws {
        let service = try service()
        switch service.status {
        case .enabled, .requiresApproval:
            try service.unregister()
            logger.notice("Menu bar helper was unregistered.")
        case .notRegistered, .notFound:
            break
        @unknown default:
            break
        }
    }

    func requiresApproval() throws -> Bool {
        try service().status == .requiresApproval
    }

    private func service() throws -> SMAppService {
        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LoginItems", isDirectory: true)
            .appendingPathComponent("HomeKitLink Menu.app", isDirectory: true)

        guard let helperBundle = Bundle(url: helperURL),
              let identifier = helperBundle.bundleIdentifier else {
            throw MenuBarHelperError.missingHelper
        }
        return SMAppService.loginItem(identifier: identifier)
    }
}

private enum MenuBarHelperError: LocalizedError {
    case missingHelper
    case unknownStatus

    var errorDescription: String? {
        switch self {
        case .missingHelper:
            "The bundled menu bar helper could not be found."
        case .unknownStatus:
            "The menu bar helper returned an unknown status."
        }
    }
}
