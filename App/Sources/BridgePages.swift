import BridgeCore
import SwiftUI

struct OverviewPage: View {
    @Bindable var model: BridgeAppModel

    var body: some View {
        Form {
            Section("Bridge") {
                LabeledContent("Server", value: serverDescription)
                LabeledContent("Home access", value: model.homeKit.isAuthorized ? "Allowed" : "Not allowed")
                LabeledContent("Home data") {
                    HomeDataStatusText(homeKit: model.homeKit)
                }
                LabeledContent(
                    "Network access",
                    value: model.isLocalNetworkEnabled ? "Local network" : "This Mac only"
                )
            }

            Section("Accessory permissions") {
                LabeledContent("Allowed", value: allowedCount.formatted())
                LabeledContent("Read only", value: count(for: .readOnly).formatted())
                LabeledContent("Read and write", value: count(for: .readWrite).formatted())
                LabeledContent("Not allowed", value: count(for: .denied).formatted())

                Text("Only allowed accessories are visible through MCP, the REST API, and CLI.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Background operation") {
                Toggle(
                    "Open at Login",
                    isOn: Binding(
                        get: { model.launchAtLogin.isRequested },
                        set: { model.setLaunchAtLogin($0) }
                    )
                )

                Toggle(
                    "Show Menu Bar Item While Running",
                    isOn: Binding(
                        get: { model.isMenuBarItemEnabled },
                        set: { model.setMenuBarItemEnabled($0) }
                    )
                )

                LabeledContent("Login status", value: model.launchAtLogin.statusDescription)
                LabeledContent("Menu bar", value: menuBarStatusDescription)

                if model.launchAtLogin.requiresApproval || model.menuBarItemRequiresApproval {
                    Button("Open Login Items Settings") {
                        model.launchAtLogin.openSystemSettings()
                    }
                }

                Text(backgroundOperationDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if model.isMenuBarItemEnabled {
                    Text("macOS manages the menu helper under Login Items. The helper is unregistered when you quit the bridge.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Overview")
    }

    private var allowedCount: Int {
        model.accessories.count { $0.access != .denied }
    }

    private func count(for access: AccessLevel) -> Int {
        model.accessories.count { $0.access == access }
    }

    private var serverDescription: String {
        switch model.serverState {
        case .stopped: "Stopped"
        case .starting: "Starting"
        case let .ready(port): "Running on port \(port)"
        case .failed: "Failed"
        }
    }

    private var backgroundOperationDescription: String {
        if model.isMenuBarItemEnabled {
            "Closing the main window keeps the local API and menu bar item running. Use Quit from the menu bar item or the app menu to stop the bridge."
        } else {
            "Closing the main window keeps the local API running. Use the Dock to reopen or quit the bridge."
        }
    }

    private var menuBarStatusDescription: String {
        if model.menuBarItemRequiresApproval {
            "Needs approval"
        } else {
            model.isMenuBarItemEnabled ? "On" : "Off"
        }
    }
}

struct APIPage: View {
    @Bindable var model: BridgeAppModel

    var body: some View {
        Form {
            Section("Connection") {
                AccessURLRow(title: "This Mac", url: model.loopbackBaseURL)
                if model.isLocalNetworkEnabled {
                    if model.localNetworkBaseURLs.isEmpty {
                        LabeledContent("Local network", value: "No active IPv4 address")
                    } else {
                        ForEach(model.localNetworkBaseURLs, id: \.self) { url in
                            AccessURLRow(title: "Local network", url: url)
                        }
                    }
                }
                LabeledContent(
                    "Availability",
                    value: model.isLocalNetworkEnabled ? "Devices on this network" : "This Mac only"
                )
                LabeledContent("Server", value: serverDescription)
                LabeledContent(
                    "Authentication",
                    value: model.isAuthenticationRequired ? "Bearer token required" : "Off"
                )
            }

            Section("Access") {
                Toggle(
                    "Allow Local Network Connections",
                    isOn: Binding(
                        get: { model.isLocalNetworkEnabled },
                        set: { model.setLocalNetworkEnabled($0) }
                    )
                )

                LabeledContent("Authentication", value: "Bearer token required")

                if model.isLocalNetworkEnabled {
                    Text("Local network traffic uses unencrypted HTTP and exposes all IPv4 interfaces, including VPN interfaces. Use only an isolated, trusted network. Never expose this port publicly.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("MCP") {
                AccessURLRow(title: "This Mac", url: model.loopbackBaseURL + "/mcp")
                if model.isLocalNetworkEnabled {
                    ForEach(model.localNetworkBaseURLs, id: \.self) { url in
                        AccessURLRow(title: "Local network", url: url + "/mcp")
                    }
                }
                LabeledContent("Transport", value: "Streamable HTTP")
                Text("Configure your MCP client with this URL and an Authorization: Bearer header using the token from Security & Logs. REST and MCP always require the token.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Tools can list permitted accessories, read values and camera motion, and write with read-and-write permission plus confirm=true. Ask before operating devices. Browser clients and OAuth sign-in are not supported.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Camera motion") {
                Text("Read camera motion through the API or CLI after granting read access in Accessories. The Mac must stay awake with the bridge running. Camera images and video are not available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Before testing") {
                if model.isAuthenticationRequired {
                    Text("Authenticated examples read the token from a shell variable and send it to curl through standard input, keeping it out of the pasted command and shell history.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    CommandRow(
                        command: "printf 'Bridge token: '; read -rs HKBRIDGE_TOKEN; printf '\\n'",
                        description: "Paste the token from Security & Logs at the hidden prompt, then press Return."
                    )
                }
                CommandRow(
                    command: "ACCESSORY_ID='PASTE_ACCESSORY_ID_HERE'",
                    description: "Copy an allowed accessory ID from the accessories response."
                )
                CommandRow(
                    command: "CHARACTERISTIC_ID='PASTE_CHARACTERISTIC_ID_HERE'",
                    description: "Copy a characteristic ID from that accessory's response."
                )
            }

            Section("Endpoints") {
                APIEndpointRow(
                    method: "GET",
                    path: "/health",
                    description: "Check whether the bridge is running.",
                    curlExample: CurlExamples.health(baseURL: model.preferredAPIBaseURL)
                )
                APIEndpointRow(
                    method: "GET",
                    path: "/v1/status",
                    description: "Read bridge and HomeKit status.",
                    curlExample: CurlExamples.status(
                        baseURL: model.preferredAPIBaseURL,
                        authenticationRequired: model.isAuthenticationRequired
                    )
                )
                APIEndpointRow(
                    method: "GET",
                    path: "/v1/accessories",
                    description: "List allowed accessories and find IDs for the examples below.",
                    curlExample: CurlExamples.accessories(
                        baseURL: model.preferredAPIBaseURL,
                        authenticationRequired: model.isAuthenticationRequired
                    )
                )
                APIEndpointRow(
                    method: "GET",
                    path: "/v1/accessories/{id}",
                    description: "Inspect one allowed accessory.",
                    curlExample: CurlExamples.accessory(
                        baseURL: model.preferredAPIBaseURL,
                        authenticationRequired: model.isAuthenticationRequired
                    )
                )
                APIEndpointRow(
                    method: "GET",
                    path: "/v1/accessories/{id}/characteristics/{id}",
                    description: "Read an allowed characteristic.",
                    curlExample: CurlExamples.readCharacteristic(
                        baseURL: model.preferredAPIBaseURL,
                        authenticationRequired: model.isAuthenticationRequired
                    )
                )
                APIEndpointRow(
                    method: "PUT",
                    path: "/v1/accessories/{id}/characteristics/{id}",
                    description: "Write an allowed characteristic. This example writes true and may operate a real device.",
                    curlExample: CurlExamples.writeCharacteristic(
                        baseURL: model.preferredAPIBaseURL,
                        authenticationRequired: model.isAuthenticationRequired
                    )
                )
                APIEndpointRow(
                    method: "GET",
                    path: "/v1/accessories/{id}/camera/motion",
                    description: "Read the current Boolean state of each HomeKit motion sensor exposed by an allowed camera.",
                    curlExample: CurlExamples.cameraMotion(
                        baseURL: model.preferredAPIBaseURL,
                        authenticationRequired: model.isAuthenticationRequired
                    )
                )
            }

            Section("Security") {
                Text(securityDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("REST API AI Skill") {
                SkillDocumentView(skill: .restAPI)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("API and MCP")
    }

    private var serverDescription: String {
        switch model.serverState {
        case .stopped: "Stopped"
        case .starting: "Starting"
        case let .ready(port): "Running on port \(port)"
        case .failed: "Failed"
        }
    }

    private var securityDescription: String {
        if model.isLocalNetworkEnabled {
            "Bearer authentication and accessory permission checks run for every request."
        } else {
            "The API listens only on this Mac. Authentication and accessory permission checks run for every request."
        }
    }
}

struct CLIPage: View {
    var body: some View {
        Form {
            Section("Useful commands") {
                CommandRow(command: "hkrelay config set-token", description: "Store the token shown in Security & Logs.")
                CommandRow(command: "hkrelay status", description: "Check the local bridge connection.")
                CommandRow(command: "hkrelay accessories list", description: "List accessories allowed in the app.")
                CommandRow(command: "hkrelay camera motion ACCESSORY_ID", description: "Read a camera's current motion state.")
            }

            Section("CLI AI Skill") {
                SkillDocumentView(skill: .cli)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("CLI")
    }
}

private struct CommandRow: View {
    let command: String
    let description: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(command)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(copied ? "Copied" : "Copy") {
                UIPasteboard.general.string = command
                copied = true
            }
        }
    }
}

private struct HomeDataStatusText: View {
    let homeKit: HomeKitRepository

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(status(at: context.date))
                .foregroundStyle(statusColor)
        }
    }

    private func status(at date: Date) -> String {
        switch homeKit.loadPhase {
        case .idle:
            "Not started"
        case .checkingAccess:
            "Checking access · \(elapsedSeconds(at: date))s"
        case .loadingHomes:
            "Loading · \(elapsedSeconds(at: date))s"
        case .ready:
            "Loaded · \(homeKit.accessories.count) \(homeKit.accessories.count == 1 ? "accessory" : "accessories")"
        case .empty:
            "Loaded · No accessories"
        case .accessDenied:
            "Access required"
        }
    }

    private var statusColor: Color {
        switch homeKit.loadPhase {
        case .accessDenied:
            .red
        case .checkingAccess, .loadingHomes:
            .secondary
        case .idle, .ready, .empty:
            .primary
        }
    }

    private func elapsedSeconds(at date: Date) -> Int {
        guard let startedAt = homeKit.loadStartedAt else { return 0 }
        return max(0, Int(date.timeIntervalSince(startedAt)))
    }
}

private struct AccessURLRow: View {
    let title: String
    let url: String
    @State private var copied = false

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text(url)
                    .textSelection(.enabled)
                Button {
                    UIPasteboard.general.string = url
                    copied = true
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel(copied ? "URL copied" : "Copy \(title) URL")
                .help("Copy \(url)")
            }
        }
        .onChange(of: url) { _, _ in copied = false }
    }
}
