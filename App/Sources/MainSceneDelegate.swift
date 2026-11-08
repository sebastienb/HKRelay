#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit
import OSLog

@MainActor
final class MainSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private let logger = Logger(subsystem: "org.homekitrestbridge.app", category: "WindowPresence")

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene,
              let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        windowScene.title = "HKRelay"
        windowScene.activationConditions.canActivateForTargetContentIdentifierPredicate =
            NSPredicate(format: "SELF != %@", CommandSceneDelegate.activityType)
        windowScene.sizeRestrictions?.minimumSize = CGSize(width: 720, height: 500)
        let root = RootView(model: appDelegate.model)
        let controller = UIHostingController(rootView: root)
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        logger.notice("Main window connected.")
        // Apply an initial size without moving a restored window to another display.
        if session.stateRestorationActivity == nil {
            windowScene.requestGeometryUpdate(UIWindowScene.GeometryPreferences.Mac(
                systemFrame: CGRect(x: 120, y: 100, width: 980, height: 680)
            ))
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        guard let model = (UIApplication.shared.delegate as? AppDelegate)?.model else { return }
        model.launchAtLogin.refresh()
        model.refreshMenuBarItemStatus()
        model.refreshNetworkAddresses()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        window = nil
        logger.notice("Main window closed.")
    }
}
#endif
