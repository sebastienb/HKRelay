import UIKit

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func applicationWillTerminate(_ application: UIApplication) {
        try? MenuBarHelperController.shared.stop()
    }
}
