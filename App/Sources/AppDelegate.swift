import UIKit

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    // Own the service for the entire process lifetime, independent of its windows.
    let model = BridgeAppModel()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        model.start()
        model.launchAtLogin.refresh()
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        try? MenuBarHelperController.shared.stop()
    }
}
