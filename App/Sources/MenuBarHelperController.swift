import OSLog
import ServiceManagement

@MainActor
final class MenuBarHelperController {
    static let shared = MenuBarHelperController()
    private static let registrationLocationKey = "menuBarHelper.registrationLocation"
    private static let helperName = "HKRelay Menu.app"

    private let logger = Logger(
        subsystem: "org.homekitrestbridge.app",
        category: "MenuBarHelper"
    )

    private init() {}

    @discardableResult
    func start() throws -> Bool {
        let service = try service()
        let location = Bundle.main.bundleURL.path + "/" + Self.helperName
        let defaults = UserDefaults.standard
        // An enabled registration can still point to a moved or renamed app.
        // Refresh legacy registrations once, then only when the location changes.
        if (service.status == .enabled || service.status == .requiresApproval),
           defaults.string(forKey: Self.registrationLocationKey) != location {
            try service.unregister()
            logger.notice("Refreshing the menu bar helper registration after an app move or upgrade.")
        }
        switch service.status {
        case .enabled:
            defaults.set(location, forKey: Self.registrationLocationKey)
            logger.notice("Menu bar helper is registered.")
            return false
        case .notRegistered, .notFound:
            try service.register()
            defaults.set(location, forKey: Self.registrationLocationKey)
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
            .appendingPathComponent(Self.helperName, isDirectory: true)

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
