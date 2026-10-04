import AppKit

@MainActor
final class MenuBarAppDelegate: NSObject, NSApplicationDelegate {
    private var controller: MenuBarStatusController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = MenuBarStatusController()
    }
}
