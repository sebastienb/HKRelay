import AppKit
import Foundation

@MainActor
final class MenuBarStatusController: NSObject {
    private let statusItem: NSStatusItem
    private let statusMenuItem = NSMenuItem(title: "Checking Bridge…", action: nil, keyEquivalent: "")
    private var timer: Timer?
    private var healthTask: Task<Void, Never>?
    private var bridgeIsRunning = false

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        configureMenu()
        updateAppearance()
        tick()
        timer = Timer.scheduledTimer(
            timeInterval: 2,
            target: self,
            selector: #selector(tick),
            userInfo: nil,
            repeats: true
        )
    }

    private func configureMenu() {
        statusItem.autosaveName = "HomeKitBridgeMenu"
        statusItem.button?.toolTip = "HomeKitLink"

        let menu = NSMenu()
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        let openItem = NSMenuItem(
            title: "Open HomeKitLink",
            action: #selector(openBridge),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)

        let quitItem = NSMenuItem(
            title: "Quit HomeKitLink",
            action: #selector(quitBridge),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func tick() {
        guard healthTask == nil else { return }
        healthTask = Task { [weak self] in
            guard let self else { return }
            defer { healthTask = nil }

            var request = URLRequest(
                url: URL(string: "http://127.0.0.1:8765/_internal/menu-bar-health")!
            )
            request.timeoutInterval = 1
            request.setValue(
                "menu-bar-health",
                forHTTPHeaderField: "X-HomeKit-Bridge-Internal"
            )

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                bridgeIsRunning = (response as? HTTPURLResponse)?.statusCode == 200
            } catch {
                bridgeIsRunning = false
            }
            updateAppearance()
        }
    }

    private var parentApplication: NSRunningApplication? {
        guard let identifier = parentBundleIdentifier else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first
    }

    private var parentBundleIdentifier: String? {
        guard let identifier = Bundle.main.bundleIdentifier,
              identifier.hasSuffix(".menu") else { return nil }
        return String(identifier.dropLast(".menu".count))
    }

    private var parentBundleURL: URL {
        Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func updateAppearance() {
        let symbolName = bridgeIsRunning ? "house.fill" : "house"
        let description = bridgeIsRunning ? "HomeKitLink running" : "HomeKitLink unavailable"
        statusItem.button?.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: description
        )
        statusMenuItem.title = bridgeIsRunning ? "Bridge Running" : "Bridge Unavailable"
        statusItem.button?.toolTip = description
    }

    @objc private func openBridge() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(
            at: parentBundleURL,
            configuration: configuration
        )
    }

    @objc private func quitBridge() {
        parentApplication?.terminate()
        NSApplication.shared.terminate(nil)
    }
}
