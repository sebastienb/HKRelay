#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit
import OSLog

@MainActor
final class CommandSceneDelegate: UIResponder, UIWindowSceneDelegate {
    static let configurationName = "HKRelay Command"
    static let activityType = "org.homekitrestbridge.command"
    var window: UIWindow?
    private let logger = Logger(subsystem: "org.homekitrestbridge.app", category: "WindowPresence")

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        windowScene.title = Self.configurationName
        windowScene.activationConditions.canActivateForTargetContentIdentifierPredicate =
            NSPredicate(format: "SELF == %@", Self.activityType)
        windowScene.titlebar?.titleVisibility = .hidden
        windowScene.titlebar?.toolbar = nil
        windowScene.titlebar?.separatorStyle = .none
        windowScene.sizeRestrictions?.minimumSize = CGSize(width: 380, height: 132)
        windowScene.sizeRestrictions?.maximumSize = CGSize(width: 380, height: 132)
        windowScene.sizeRestrictions?.allowsFullScreen = false

        let controller = UIHostingController(rootView: CommandNotificationView(activity: WindowPresence.shared.activity))
        controller.view.backgroundColor = .clear
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        position(windowScene)
        WindowPresence.shared.commandSceneConnected(windowScene)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        if let windowScene = scene as? UIWindowScene {
            position(windowScene)
            logger.notice("Command geometry: \(String(describing: windowScene.effectiveGeometry.systemFrame), privacy: .public), screen: \(String(describing: windowScene.screen.bounds), privacy: .public), scale: \(windowScene.screen.scale), native scale: \(windowScene.screen.nativeScale).")
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        WindowPresence.shared.commandSceneDisconnected(scene.session)
        window = nil
    }

    func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? { nil }

    private func position(_ scene: UIWindowScene) {
        // Geometry requests use system coordinates with the main display's top-left at zero.
        let display = UIScreen.main.bounds
        let frame = CGRect(x: max(display.minX, display.maxX - 398), y: display.minY + 42, width: 380, height: 132)
        scene.requestGeometryUpdate(UIWindowScene.GeometryPreferences.Mac(systemFrame: frame))
    }
}
#endif
