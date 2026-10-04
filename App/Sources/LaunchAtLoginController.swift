import Observation
import ServiceManagement

@MainActor
@Observable
final class LaunchAtLoginController {
    private(set) var status: SMAppService.Status

    init() {
        status = SMAppService.mainApp.status
    }

    var isRequested: Bool {
        status == .enabled || status == .requiresApproval
    }

    var requiresApproval: Bool {
        status == .requiresApproval
    }

    var statusDescription: String {
        switch status {
        case .notRegistered:
            "Off"
        case .enabled:
            "On"
        case .requiresApproval:
            "Needs approval"
        case .notFound:
            "Unavailable"
        @unknown default:
            "Unknown"
        }
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp

        if enabled {
            guard service.status == .notRegistered || service.status == .notFound else {
                refresh()
                return
            }
            try service.register()
        } else {
            guard service.status != .notRegistered else {
                refresh()
                return
            }
            try service.unregister()
        }

        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
