import BridgeCore
import BridgeServer
import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class BridgeAppModel {
    private static let menuBarItemEnabledKey = "menuBarHelper.enabled"
    private static let localNetworkEnabledKey = "server.local-network.enabled"

    let homeKit = HomeKitRepository()
    let launchAtLogin = LaunchAtLoginController()
    let requestHistory = RequestHistoryStore()

    private(set) var serverState: ServerState = .stopped
    private(set) var apiToken: String = ""
    private(set) var lastError: String?
    private(set) var isMenuBarItemEnabled: Bool
    private(set) var menuBarItemRequiresApproval = false
    private(set) var isLocalNetworkEnabled: Bool
    let isAuthenticationRequired = true
    private(set) var localNetworkAddresses: [String]

    @ObservationIgnored private let tokenStore = TokenStore()
    @ObservationIgnored private let logger = Logger(
        subsystem: "org.homekitrestbridge.app",
        category: "Startup"
    )
    @ObservationIgnored private var server: LocalHTTPServer?
    @ObservationIgnored private var router: BridgeRouter?
    @ObservationIgnored private var isRestartingServer = false
    @ObservationIgnored private let menuBarHelper = MenuBarHelperController.shared
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isMenuBarItemEnabled = defaults.bool(forKey: Self.menuBarItemEnabledKey)
        isLocalNetworkEnabled = defaults.bool(forKey: Self.localNetworkEnabledKey)
        localNetworkAddresses = LocalNetworkAddressProvider.ipv4Addresses()
    }

    var accessories: [AccessoryDescriptor] {
        homeKit.accessories
    }

    var loopbackBaseURL: String {
        "http://127.0.0.1:8765"
    }

    var localNetworkBaseURLs: [String] {
        localNetworkAddresses.map { "http://\($0):8765" }
    }

    var preferredAPIBaseURL: String {
        if isLocalNetworkEnabled, let networkURL = localNetworkBaseURLs.first {
            return networkURL
        }
        return loopbackBaseURL
    }

    func start() {
        guard server == nil else { return }

        logger.notice("Bridge startup began.")
        if isMenuBarItemEnabled {
            do {
                menuBarItemRequiresApproval = try menuBarHelper.start()
            } catch {
                logger.error("Menu bar helper failed: \(error.localizedDescription, privacy: .public)")
                isMenuBarItemEnabled = false
                menuBarItemRequiresApproval = false
                defaults.set(false, forKey: Self.menuBarItemEnabledKey)
                lastError = error.localizedDescription
            }
        } else {
            try? menuBarHelper.stop()
        }

        do {
            apiToken = try tokenStore.loadOrCreateToken()
            homeKit.start()

            let router = BridgeRouter(
                homeKit: homeKit,
                token: apiToken,
                loopbackOnly: !isLocalNetworkEnabled,
                history: requestHistory
            )

            self.router = router
            startHTTPServer()
        } catch {
            logger.error("Bridge startup failed: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
            serverState = .failed(error.localizedDescription)
        }
    }

    func setAccess(_ access: AccessLevel, for accessoryID: String) {
        do {
            try homeKit.setAccess(access, for: accessoryID)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func retryHomeKit() {
        homeKit.retryLoading()
    }

    func regenerateToken() {
        do {
            let token = try tokenStore.regenerateToken()
            apiToken = token
            router?.replaceToken(token)
        } catch {
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    func setToken(_ value: String) -> Bool {
        do {
            let token = try tokenStore.setToken(value)
            apiToken = token
            router?.replaceToken(token)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func setLocalNetworkEnabled(_ enabled: Bool) {
        guard enabled != isLocalNetworkEnabled else { return }
        isLocalNetworkEnabled = enabled
        refreshNetworkAddresses()
        defaults.set(enabled, forKey: Self.localNetworkEnabledKey)
        router?.setLoopbackOnly(!enabled)
        restartHTTPServer()
    }

    func refreshNetworkAddresses() {
        localNetworkAddresses = LocalNetworkAddressProvider.ipv4Addresses()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLogin.setEnabled(enabled)
        } catch {
            lastError = "Open at Login could not be updated: \(error.localizedDescription)"
        }
    }

    func setMenuBarItemEnabled(_ enabled: Bool) {
        do {
            if enabled {
                menuBarItemRequiresApproval = try menuBarHelper.start()
            } else {
                try menuBarHelper.stop()
                menuBarItemRequiresApproval = false
            }
            isMenuBarItemEnabled = enabled
            defaults.set(enabled, forKey: Self.menuBarItemEnabledKey)
        } catch {
            lastError = "The menu bar item could not be updated: \(error.localizedDescription)"
        }
    }

    func refreshMenuBarItemStatus() {
        guard isMenuBarItemEnabled else {
            menuBarItemRequiresApproval = false
            return
        }

        do {
            menuBarItemRequiresApproval = try menuBarHelper.requiresApproval()
        } catch {
            logger.error("Menu bar helper status failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func clearError() {
        lastError = nil
    }

    private func restartHTTPServer() {
        guard router != nil, !isRestartingServer else { return }
        isRestartingServer = true

        guard let server else {
            isRestartingServer = false
            startHTTPServer()
            return
        }

        self.server = nil
        server.stop { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                isRestartingServer = false
                startHTTPServer()
            }
        }
    }

    private func startHTTPServer() {
        guard let router else { return }

        let binding: ServerBinding = isLocalNetworkEnabled ? .localNetwork : .loopback
        let server = LocalHTTPServer(port: 8765, binding: binding) { request in
            await router.handle(request)
        }
        self.server = server

        server.start { [weak self, weak server] state in
            Task { @MainActor [weak self, weak server] in
                guard let self, self.server === server else { return }
                serverState = state
                switch state {
                case let .ready(port):
                    let scope = isLocalNetworkEnabled ? "local network" : "loopback"
                    logger.notice("HTTP server ready on \(scope, privacy: .public) port \(port, privacy: .public).")
                case let .failed(message):
                    logger.error("HTTP server failed: \(message, privacy: .public)")
                    lastError = message
                case .stopped, .starting:
                    break
                }
            }
        }
    }
}
