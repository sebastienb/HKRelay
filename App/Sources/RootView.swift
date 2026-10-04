import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var model: BridgeAppModel
    @State private var section: AppSection? = .overview

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                ForEach(AppSection.allCases) { item in
                    HStack {
                        Label(item.title, systemImage: item.systemImage)
                        Spacer()
                        if item == .accessories, !model.accessories.isEmpty {
                            Text(model.accessories.count.formatted())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        } else if item == .securityAndLogs, !model.requestHistory.records.isEmpty {
                            Text(model.requestHistory.records.count.formatted())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .tag(item)
                }
            }
            .navigationTitle("HKRelay")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            NavigationStack {
                switch section ?? .overview {
                case .overview:
                    OverviewPage(model: model)
                case .accessories:
                    AccessoryBrowserView(model: model)
                case .api:
                    APIPage(model: model)
                case .cli:
                    CLIPage()
                case .securityAndLogs:
                    HistoryPage(model: model, history: model.requestHistory)
                }
            }
        }
        .alert("Bridge Error", isPresented: errorPresented) {
            Button("OK") { model.clearError() }
        } message: {
            Text(model.lastError ?? "Unknown error")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.launchAtLogin.refresh()
                model.refreshMenuBarItemStatus()
                model.refreshNetworkAddresses()
            }
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.clearError() } }
        )
    }
}

private enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case accessories
    case api
    case cli
    case securityAndLogs

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .accessories: "Accessories"
        case .api: "API and MCP"
        case .cli: "CLI"
        case .securityAndLogs: "Security & Logs"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "chart.bar.xaxis"
        case .accessories: "square.grid.2x2"
        case .api: "network"
        case .cli: "terminal"
        case .securityAndLogs: "lock.shield"
        }
    }
}
