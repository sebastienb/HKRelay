import SwiftUI

@main
struct HomeKitRESTBridgeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = BridgeAppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .frame(minWidth: 720, minHeight: 500)
                .background {
                    CatalystWindowSizeConfigurator(
                        minimumSize: CGSize(width: 720, height: 500)
                    )
                }
                .onAppear {
                    model.start()
                    model.launchAtLogin.refresh()
                }
        }
        .defaultSize(width: 980, height: 680)
    }
}
