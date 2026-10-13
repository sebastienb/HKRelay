import SwiftUI

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
