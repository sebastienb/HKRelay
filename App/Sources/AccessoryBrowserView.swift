import BridgeCore
import Foundation
import SwiftUI

struct AccessoryBrowserView: View {
    @Bindable var model: BridgeAppModel
    @State private var searchText = ""
    @State private var accessFilter = AccessoryAccessFilter.all

    var body: some View {
        Group {
            if model.accessories.isEmpty {
                AccessoryBrowserEmptyState(homeKit: model.homeKit) {
                    model.retryHomeKit()
                }
            } else {
                VStack(spacing: 0) {
                    filterBar
                    Divider()
                    accessoryList
                }
            }
        }
        .navigationTitle("Accessories")
        .searchable(text: $searchText, prompt: "Search name, room, or type")
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            Picker("Show", selection: $accessFilter) {
                ForEach(AccessoryAccessFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 220, alignment: .leading)

            Spacer()

            Text("\(filteredAccessories.count) of \(model.accessories.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var accessoryList: some View {
        if filteredAccessories.isEmpty {
            ContentUnavailableView(
                "No matching accessories",
                systemImage: "magnifyingglass",
                description: Text("Try another search or access filter.")
            )
        } else {
            List {
                if !allowedAccessories.isEmpty {
                    Section {
                        ForEach(allowedAccessories) { accessory in
                            accessoryLink(accessory)
                        }
                    } header: {
                        AccessorySectionHeader(
                            title: "Allowed",
                            count: allowedAccessories.count,
                            systemImage: "checkmark.shield.fill"
                        )
                    }
                }

                if !deniedAccessories.isEmpty {
                    Section {
                        ForEach(deniedAccessories) { accessory in
                            accessoryLink(accessory)
                        }
                    } header: {
                        AccessorySectionHeader(
                            title: "Not Allowed",
                            count: deniedAccessories.count,
                            systemImage: "lock.fill"
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func accessoryLink(_ accessory: AccessoryDescriptor) -> some View {
        NavigationLink {
            AccessoryDetailHost(model: model, accessoryID: accessory.id)
        } label: {
            AccessoryBrowserRow(accessory: accessory)
        }
    }

    private var filteredAccessories: [AccessoryDescriptor] {
        model.accessories.filter { accessory in
            accessFilter.includes(accessory.access) && matchesSearch(accessory)
        }
    }

    private var allowedAccessories: [AccessoryDescriptor] {
        filteredAccessories.filter { $0.access != .denied }
    }

    private var deniedAccessories: [AccessoryDescriptor] {
        filteredAccessories.filter { $0.access == .denied }
    }

    private func matchesSearch(_ accessory: AccessoryDescriptor) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        return [accessory.name, accessory.room, accessory.category]
            .compactMap { $0 }
            .contains { $0.localizedStandardContains(query) }
    }
}

private enum AccessoryAccessFilter: String, CaseIterable, Identifiable {
    case all
    case allowed
    case readOnly
    case readWrite
    case denied

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All accessories"
        case .allowed: "Allowed"
        case .readOnly: "Read only"
        case .readWrite: "Read and write"
        case .denied: "Not allowed"
        }
    }

    func includes(_ access: AccessLevel) -> Bool {
        switch self {
        case .all: true
        case .allowed: access != .denied
        case .readOnly: access == .readOnly
        case .readWrite: access == .readWrite
        case .denied: access == .denied
        }
    }
}

private struct AccessorySectionHeader: View {
    let title: String
    let count: Int
    let systemImage: String

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(count.formatted())
                .monospacedDigit()
        }
    }
}

private struct AccessoryBrowserRow: View {
    let accessory: AccessoryDescriptor

    var body: some View {
        HStack(spacing: 12) {
            AccessoryTypeIcon(accessory: accessory)

            VStack(alignment: .leading, spacing: 4) {
                Text(accessory.name)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    Label(accessory.category, systemImage: "tag")
                    if let room = accessory.room {
                        Label(room, systemImage: "house")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                AccessoryPermissionBadge(access: accessory.access)

                if !accessory.reachable {
                    Label("Unavailable", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct AccessoryTypeIcon: View {
    let accessory: AccessoryDescriptor

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 38, height: 38)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
            .accessibilityLabel(accessory.category)
    }

    private var tint: Color {
        switch accessory.access {
        case .denied: .gray
        case .readOnly: .blue
        case .readWrite: .green
        }
    }

    private var symbolName: String {
        let type = "\(accessory.categoryType ?? "") \(accessory.category)".lowercased()

        if type.contains("lightbulb") || type.contains("light bulb") { return "lightbulb.fill" }
        if type.contains("outlet") { return "powerplug.fill" }
        if type.contains("programmable switch") || type.contains("switch") { return "switch.2" }
        if type.contains("thermostat") || type.contains("air heater") || type.contains("air conditioner") { return "thermometer.medium" }
        if type.contains("fan") { return "fan.fill" }
        if type.contains("garage") { return "car.fill" }
        if type.contains("doorbell") { return "bell.fill" }
        if type.contains("door lock") || type.contains("lock") { return "lock.fill" }
        if type.contains("door") { return "door.left.hand.closed" }
        if type.contains("window covering") || type.contains("blind") || type.contains("shade") { return "rectangle.split.3x1" }
        if type.contains("window") { return "window.vertical.closed" }
        if type.contains("security") { return "shield.fill" }
        if type.contains("camera") { return "video.fill" }
        if type.contains("smoke") { return "smoke.fill" }
        if type.contains("sensor") { return "sensor.fill" }
        if type.contains("bridge") || type.contains("range extender") || type.contains("router") || type.contains("airport") { return "wifi.router.fill" }
        if type.contains("purifier") || type.contains("air quality") { return "aqi.medium" }
        if type.contains("humidifier") || type.contains("dehumidifier") { return "drop.fill" }
        if type.contains("sprinkler") || type.contains("faucet") || type.contains("shower") || type.contains("valve") { return "drop.fill" }
        if type.contains("television") || type.contains("set top") || type.contains("streaming") { return "tv.fill" }
        if type.contains("speaker") || type.contains("receiver") { return "speaker.wave.2.fill" }
        return "cube.fill"
    }
}

private struct AccessoryPermissionBadge: View {
    let access: AccessLevel

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private var title: String {
        switch access {
        case .denied: "Not Allowed"
        case .readOnly: "Read Only"
        case .readWrite: "Read & Write"
        }
    }

    private var systemImage: String {
        switch access {
        case .denied: "lock.fill"
        case .readOnly: "eye.fill"
        case .readWrite: "pencil"
        }
    }

    private var tint: Color {
        switch access {
        case .denied: .gray
        case .readOnly: .blue
        case .readWrite: .green
        }
    }
}

private struct AccessoryDetailHost: View {
    @Bindable var model: BridgeAppModel
    let accessoryID: String

    var body: some View {
        if let accessory = model.accessories.first(where: { $0.id == accessoryID }) {
            AccessoryPermissionDetailView(accessory: accessory) { access in
                model.setAccess(access, for: accessory.id)
            }
        } else {
            ContentUnavailableView("Accessory unavailable", systemImage: "house.slash")
        }
    }
}

private struct AccessoryPermissionDetailView: View {
    let accessory: AccessoryDescriptor
    let setAccess: (AccessLevel) -> Void

    var body: some View {
        Form {
            Section("Permission") {
                Picker(
                    "REST and CLI access",
                    selection: Binding(
                        get: { accessory.access },
                        set: { access in setAccess(access) }
                    )
                ) {
                    Text("Not allowed").tag(AccessLevel.denied)
                    Text("Read only").tag(AccessLevel.readOnly)
                    Text("Read and write").tag(AccessLevel.readWrite)
                }
                .pickerStyle(.segmented)

                Text("Not allowed is the default. The bridge checks this setting for every request.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Device") {
                LabeledContent("Name", value: accessory.name)
                LabeledContent("Room", value: accessory.room ?? "Unassigned")
                LabeledContent("Type", value: accessory.category)
                if let manufacturer = accessory.manufacturer, !manufacturer.isEmpty {
                    LabeledContent("Manufacturer", value: manufacturer)
                }
                if let model = accessory.model, !model.isEmpty {
                    LabeledContent("Model", value: model)
                }
                if let firmwareVersion = accessory.firmwareVersion, !firmwareVersion.isEmpty {
                    LabeledContent("Firmware", value: firmwareVersion)
                }
                LabeledContent("Reachable", value: accessory.reachable ? "Yes" : "No")
                if let camera = accessory.camera {
                    LabeledContent("HomeKit motion", value: camera.motionCharacteristicIDs.isEmpty ? "Not exposed" : "Available")
                }
            }

            ForEach(accessory.services) { service in
                Section(service.name) {
                    ForEach(service.characteristics) { characteristic in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(characteristic.name)
                                Text(capabilities(for: characteristic))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let value = characteristic.value {
                                Text(display(value))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(accessory.name)
    }

    private func capabilities(for characteristic: CharacteristicDescriptor) -> String {
        switch (characteristic.readable, characteristic.writable) {
        case (true, true): "Readable and writable"
        case (true, false): "Readable"
        case (false, true): "Writable"
        case (false, false): "Not exposed by HomeKit"
        }
    }

    private func display(_ value: JSONValue) -> String {
        switch value {
        case .null: "null"
        case let .bool(value): value ? "true" : "false"
        case let .number(value): value.formatted()
        case let .string(value): value
        case .array: "Array"
        case .object: "Object"
        }
    }
}

private struct AccessoryBrowserEmptyState: View {
    let homeKit: HomeKitRepository
    let retry: () -> Void

    var body: some View {
        Group {
            switch homeKit.loadPhase {
            case .checkingAccess, .loadingHomes:
                loadingContent
            case .accessDenied:
                VStack(spacing: 12) {
                    ContentUnavailableView(
                        "Home access required",
                        systemImage: "house.badge.exclamationmark",
                        description: Text("Allow Home access in System Settings, then check again.")
                    )
                    Button("Check Again", action: retry)
                }
            case .empty:
                VStack(spacing: 12) {
                    ContentUnavailableView(
                        "No accessories found",
                        systemImage: "house.slash",
                        description: Text(emptyDescription)
                    )
                    Button("Reload HomeKit", action: retry)
                }
            case .idle:
                VStack(spacing: 12) {
                    ContentUnavailableView("HomeKit has not started", systemImage: "house.slash")
                    Button("Start HomeKit", action: retry)
                }
            case .ready:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingContent: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = elapsedSeconds(at: context.date)

            VStack(spacing: 12) {
                ProgressView("Loading HomeKit data")
                    .controlSize(.large)
                Text(loadingTitle)
                    .font(.headline)
                Text("Waiting for \(elapsed) \(elapsed == 1 ? "second" : "seconds").")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if elapsed >= 15 {
                    Label("This is taking longer than expected.", systemImage: "clock.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("Check that the Home app can load your home, then try again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Try Again", action: retry)
                }
            }
            .padding()
        }
    }

    private var loadingTitle: String {
        switch homeKit.loadPhase {
        case .checkingAccess: "Checking Home access…"
        case .loadingHomes: "Loading homes and accessories…"
        default: "Loading HomeKit data…"
        }
    }

    private var emptyDescription: String {
        if homeKit.loadedHomeCount == 0 {
            "HomeKit finished loading, but returned no homes."
        } else {
            "HomeKit loaded \(homeKit.loadedHomeCount) \(homeKit.loadedHomeCount == 1 ? "home" : "homes"), but returned no accessories."
        }
    }

    private func elapsedSeconds(at date: Date) -> Int {
        guard let startedAt = homeKit.loadStartedAt else { return 0 }
        return max(0, Int(date.timeIntervalSince(startedAt)))
    }
}
