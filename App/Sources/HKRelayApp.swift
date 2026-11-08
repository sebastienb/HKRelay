import SwiftUI

#if targetEnvironment(macCatalyst)
import UIKit

// UIKit owns the two distinct scene roles on Mac. The configuration UI itself
// remains SwiftUI, hosted by MainSceneDelegate.
@main
enum HKRelayApp {
    @MainActor
    static func main() {
        UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AppDelegate.self))
    }
}
#else
@main
struct HKRelayApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView(model: appDelegate.model)
                .frame(minWidth: 720, minHeight: 500)
                .background {
                    CatalystWindowSizeConfigurator(
                        minimumSize: CGSize(width: 720, height: 500)
                    )
                }
        }
        .defaultSize(width: 980, height: 680)
    }
}
#endif
