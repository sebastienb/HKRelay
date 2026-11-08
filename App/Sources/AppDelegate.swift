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

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        #if targetEnvironment(macCatalyst)
        if options.userActivities.contains(where: { $0.activityType == CommandSceneDelegate.activityType }) {
            let configuration = UISceneConfiguration(
                name: CommandSceneDelegate.configurationName,
                sessionRole: connectingSceneSession.role
            )
            configuration.sceneClass = UIWindowScene.self
            configuration.delegateClass = CommandSceneDelegate.self
            return configuration
        }
        let configuration = UISceneConfiguration(name: "HKRelay", sessionRole: connectingSceneSession.role)
        configuration.sceneClass = UIWindowScene.self
        configuration.delegateClass = MainSceneDelegate.self
        return configuration
        #else
        // Do not return SwiftUI's internal delegate as its own fallback delegate.
        return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        #endif
    }
}
