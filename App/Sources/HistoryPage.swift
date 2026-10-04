import BridgeCore
import SwiftUI

struct HistoryPage: View {
    @Bindable var model: BridgeAppModel
    @Bindable var history: RequestHistoryStore
    @State private var searchText = ""
    @State private var methodFilter: MethodFilter = .all
    @State private var resultFilter: ResultFilter = .all
    @State private var clientFilter: ClientFilter = .all
    @State private var tokenVisible = false
    @State private var tokenCopied = false
    @State private var editingCustomToken = false
    @State private var customToken = ""
    @State private var pendingConfirmation: PendingConfirmation?
    @FocusState private var customTokenFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            tokenControls
            Divider()
            controls
            Divider()

            if let persistenceIssue = history.persistenceIssue {
                Label(persistenceIssue, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                Divider()
            }

            historyContent
        }
        .navigationTitle("Security & Logs")
        .searchable(text: $searchText, prompt: "Filter requests")
        .confirmationDialog(
            confirmationTitle,
            isPresented: confirmationPresented,
            titleVisibility: .visible
        ) {
            if pendingConfirmation == .clearHistory {
                Button("Clear History", role: .destructive) {
                    history.clear()
                }
            } else if pendingConfirmation == .regenerateToken {
                Button("Generate New Token", role: .destructive) {
                    model.regenerateToken()
                    tokenVisible = false
                    tokenCopied = false
                }
            }
        } message: {
            if pendingConfirmation == .clearHistory {
                Text("This cannot be undone. Request logging will remain \(history.isLoggingEnabled ? "on" : "off").")
            } else if pendingConfirmation == .regenerateToken {
                Text("Existing API and CLI clients will need the new token.")
            }
        }
    }

    private var tokenControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("API Authentication")
                .font(.headline)

            HStack(spacing: 12) {
                Text(tokenVisible ? model.apiToken : String(repeating: "•", count: 28))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 12)

                Button {
                    tokenVisible.toggle()
                } label: {
                    Label(tokenVisible ? "Hide" : "Reveal", systemImage: tokenVisible ? "eye.slash" : "eye")
                }

                Button {
                    UIPasteboard.general.string = model.apiToken
                    tokenCopied = true
                } label: {
                    Label(tokenCopied ? "Copied" : "Copy", systemImage: tokenCopied ? "checkmark" : "doc.on.doc")
                }
            }

            Text("Use this bearer token for REST, MCP, and hkbridge clients. Keep it out of source code, URLs, screenshots, and logs.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if editingCustomToken {
                SecureField("Custom token", text: $customToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($customTokenFocused)

                Text("Use 16-128 letters, numbers, hyphens, periods, underscores, or tildes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button {
                        if model.setToken(customToken) {
                            customToken = ""
                            editingCustomToken = false
                            tokenVisible = false
                            tokenCopied = false
                        }
                    } label: {
                        Label("Save Token", systemImage: "checkmark")
                    }
                    .disabled(!TokenStore.isValidCustomToken(customToken))

                    Button {
                        customToken = ""
                        editingCustomToken = false
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                }
            } else {
                HStack {
                    Button {
                        editingCustomToken = true
                        customTokenFocused = true
                    } label: {
                        Label("Set Custom Token", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        pendingConfirmation = .regenerateToken
                    } label: {
                        Label("Generate New Token", systemImage: "arrow.clockwise")
                    }
                }
            }


        }
        .padding()
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Toggle("Record request history", isOn: $history.isLoggingEnabled)
                    .toggleStyle(.switch)

                if !history.isLoggingEnabled {
                    Label("Paused", systemImage: "pause.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Clear History", role: .destructive) {
                    pendingConfirmation = .clearHistory
                }
                .disabled(history.records.isEmpty)
            }

            HStack(spacing: 16) {
                Picker("Method", selection: $methodFilter) {
                    ForEach(MethodFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .frame(maxWidth: 180)

                Picker("Result", selection: $resultFilter) {
                    ForEach(ResultFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .frame(maxWidth: 180)

                Picker("Client", selection: $clientFilter) {
                    ForEach(ClientFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .frame(maxWidth: 210)

                Spacer()

                Text("Showing \(filteredRecords.count) of \(history.records.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Text("The newest 500 requests are saved only in this app's private container. Authentication headers are never recorded; query strings and sensitive JSON fields are redacted.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    @ViewBuilder
    private var historyContent: some View {
        if history.records.isEmpty {
            ContentUnavailableView(
                "No Requests Yet",
                systemImage: history.isLoggingEnabled ? "clock.arrow.circlepath" : "pause.circle",
                description: Text(
                    history.isLoggingEnabled
                        ? "API and CLI requests will appear here. Internal menu-bar health checks are excluded."
                        : "Turn on request history to record new API and CLI activity."
                )
            )
        } else if filteredRecords.isEmpty {
            ContentUnavailableView.search(text: searchText.isEmpty ? "current filters" : searchText)
        } else {
            List(filteredRecords) { record in
                RequestHistoryRow(record: record)
            }
            .listStyle(.plain)
        }
    }

    private var filteredRecords: [RequestHistoryRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return history.records.filter { record in
            methodFilter.matches(record)
                && resultFilter.matches(record)
                && clientFilter.matches(record)
                && (query.isEmpty || searchableText(for: record).contains(query))
        }
    }

    private func searchableText(for record: RequestHistoryRecord) -> String {
        [
            record.method,
            record.path,
            record.client.displayName,
            String(record.statusCode),
            record.requestBody ?? ""
        ]
        .joined(separator: " ")
        .lowercased()
    }

    private var confirmationTitle: String {
        switch pendingConfirmation {
        case .clearHistory:
            "Clear all saved request history?"
        case .regenerateToken:
            "Existing clients will stop working."
        case nil:
            "Are you sure?"
        }
    }

    private var confirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingConfirmation != nil },
            set: { if !$0 { pendingConfirmation = nil } }
        )
    }

    private enum PendingConfirmation {
        case clearHistory
        case regenerateToken
    }
}

private struct RequestHistoryRow: View {
    let record: RequestHistoryRecord
    @State private var bodyExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(record.method)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(methodColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(methodColor.opacity(0.12), in: Capsule())

                Text(record.path)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)

                Spacer(minLength: 12)

                Label(String(record.statusCode), systemImage: statusImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .monospacedDigit()
            }

            HStack(spacing: 12) {
                Label(record.client.displayName, systemImage: clientImage)
                Text(record.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute().second())
                Text("\(record.durationMilliseconds.formatted()) ms")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let requestBody = record.requestBody {
                DisclosureGroup("Request body", isExpanded: $bodyExpanded) {
                    ScrollView(.horizontal) {
                        Text(requestBody)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 5)
        .contextMenu {
            Button {
                UIPasteboard.general.string = copyText
            } label: {
                Label("Copy Request Details", systemImage: "doc.on.doc")
            }
        }
    }

    private var methodColor: Color {
        switch record.method {
        case "GET": .blue
        case "PUT": .orange
        default: .secondary
        }
    }

    private var statusColor: Color {
        (200..<300).contains(record.statusCode) ? .green : .red
    }

    private var statusImage: String {
        (200..<300).contains(record.statusCode) ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
    }

    private var clientImage: String {
        switch record.client {
        case .cli: "terminal"
        case .curl: "chevron.left.forwardslash.chevron.right"
        case .browser: "safari"
        case .apiClient: "network"
        }
    }

    private var copyText: String {
        var lines = [
            "\(record.method) \(record.path)",
            "Client: \(record.client.displayName)",
            "Result: \(record.statusCode)",
            "Duration: \(record.durationMilliseconds) ms"
        ]
        if let requestBody = record.requestBody {
            lines.append("Body:\n\(requestBody)")
        }
        return lines.joined(separator: "\n")
    }
}

private enum MethodFilter: String, CaseIterable, Identifiable {
    case all
    case get
    case put
    case other

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All methods"
        case .get: "GET"
        case .put: "PUT"
        case .other: "Other"
        }
    }

    func matches(_ record: RequestHistoryRecord) -> Bool {
        switch self {
        case .all: true
        case .get: record.method == "GET"
        case .put: record.method == "PUT"
        case .other: record.method != "GET" && record.method != "PUT"
        }
    }
}

private enum ResultFilter: String, CaseIterable, Identifiable {
    case all
    case successful
    case failed

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All results"
        case .successful: "Successful"
        case .failed: "Failed"
        }
    }

    func matches(_ record: RequestHistoryRecord) -> Bool {
        switch self {
        case .all: true
        case .successful: (200..<300).contains(record.statusCode)
        case .failed: !(200..<300).contains(record.statusCode)
        }
    }
}

private enum ClientFilter: String, CaseIterable, Identifiable {
    case all
    case cli
    case curl
    case browser
    case apiClient

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All clients"
        case .cli: RequestClientKind.cli.displayName
        case .curl: RequestClientKind.curl.displayName
        case .browser: RequestClientKind.browser.displayName
        case .apiClient: RequestClientKind.apiClient.displayName
        }
    }

    func matches(_ record: RequestHistoryRecord) -> Bool {
        switch self {
        case .all: true
        case .cli: record.client == .cli
        case .curl: record.client == .curl
        case .browser: record.client == .browser
        case .apiClient: record.client == .apiClient
        }
    }
}
