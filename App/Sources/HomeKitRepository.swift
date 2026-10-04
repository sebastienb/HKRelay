@preconcurrency import HomeKit
import BridgeCore
import Foundation
import Observation

enum HomeKitLoadPhase: Equatable {
    case idle
    case checkingAccess
    case loadingHomes
    case ready
    case empty
    case accessDenied

    var isLoading: Bool {
        self == .checkingAccess || self == .loadingHomes
    }
}

@MainActor
@Observable
final class HomeKitRepository: NSObject, @preconcurrency HMHomeManagerDelegate {
    private(set) var accessories: [AccessoryDescriptor] = []
    private(set) var homeDataLoaded = false
    private(set) var authorizationStatus: HMHomeManagerAuthorizationStatus = []
    private(set) var loadStartedAt: Date?
    private(set) var loadedHomeCount = 0

    @ObservationIgnored private var homeManager: HMHomeManager?
    @ObservationIgnored private let policyStore = PolicyStore()
    @ObservationIgnored private var accessoryIndex: [String: HMAccessory] = [:]
    @ObservationIgnored private var characteristicIndex: [String: HMCharacteristic] = [:]

    var isAuthorized: Bool {
        authorizationStatus.contains(.authorized)
    }

    var loadPhase: HomeKitLoadPhase {
        guard homeManager != nil else { return .idle }

        if authorizationStatus.contains(.restricted)
            || (authorizationStatus.contains(.determined) && !isAuthorized) {
            return .accessDenied
        }
        guard isAuthorized else { return .checkingAccess }
        guard homeDataLoaded else { return .loadingHomes }
        return accessories.isEmpty ? .empty : .ready
    }

    func start() {
        guard homeManager == nil else { return }

        loadStartedAt = Date()
        homeDataLoaded = false
        loadedHomeCount = 0

        let manager = HMHomeManager()
        manager.delegate = self
        homeManager = manager
        authorizationStatus = manager.authorizationStatus
    }

    func retryLoading() {
        homeManager?.delegate = nil
        homeManager = nil
        authorizationStatus = []
        accessories = []
        accessoryIndex = [:]
        characteristicIndex = [:]
        start()
    }

    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        guard manager === homeManager else { return }
        authorizationStatus = manager.authorizationStatus
        homeDataLoaded = true
        loadedHomeCount = manager.homes.count
        rebuildIndex(from: manager.homes)
    }

    func homeManager(_ manager: HMHomeManager, didUpdate status: HMHomeManagerAuthorizationStatus) {
        guard manager === homeManager else { return }
        authorizationStatus = status
        if status.contains(.authorized) {
            rebuildIndex(from: manager.homes)
        } else {
            accessories = []
            accessoryIndex = [:]
            characteristicIndex = [:]
        }
    }

    func setAccess(_ access: AccessLevel, for accessoryID: String) throws {
        try policyStore.setAccess(access, for: accessoryID)
        if let manager = homeManager {
            rebuildIndex(from: manager.homes)
        }
    }

    func permittedAccessories() -> [AccessoryDescriptor] {
        guard isAuthorized else { return [] }
        return accessories.filter { $0.access != .denied }.map(\.discoverySnapshot)
    }

    func permittedAccessory(id: String) throws -> AccessoryDescriptor {
        try requireAuthorization()
        guard let accessory = accessories.first(where: { $0.id == id }) else {
            throw APIError(code: "not_found", message: "Accessory not found.")
        }
        guard accessory.access != .denied else {
            throw APIError(code: "access_denied", message: "This accessory is not exposed by the bridge.")
        }
        return accessory.discoverySnapshot
    }

    func read(accessoryID: String, characteristicID: String) async throws -> CharacteristicValue {
        try Task.checkCancellation()
        try requireAuthorization()
        let access = policyStore.document.access(
            for: accessoryID,
            characteristicID: characteristicID
        )
        guard access.allowsRead else {
            throw APIError(code: "read_denied", message: "Read access is disabled for this characteristic.")
        }

        let characteristic = try characteristic(accessoryID: accessoryID, characteristicID: characteristicID)
        guard characteristic.properties.contains(HMCharacteristicPropertyReadable) else {
            throw APIError(code: "not_readable", message: "HomeKit reports that this characteristic is not readable.")
        }

        try await characteristic.readValue()
        try Task.checkCancellation()
        try requireAuthorization()
        guard policyStore.document.access(for: accessoryID, characteristicID: characteristicID).allowsRead,
              characteristicIndex[indexKey(accessoryID, characteristicID)] === characteristic else {
            throw APIError(code: "read_denied", message: "Access changed while the read was pending.")
        }
        return CharacteristicValue(
            accessoryID: accessoryID,
            characteristicID: characteristicID,
            value: try jsonValue(for: characteristic)
        )
    }

    func write(
        accessoryID: String,
        characteristicID: String,
        value: JSONValue
    ) async throws -> CharacteristicValue {
        try Task.checkCancellation()
        try requireAuthorization()
        let access = policyStore.document.access(
            for: accessoryID,
            characteristicID: characteristicID
        )
        guard access.allowsWrite else {
            throw APIError(code: "write_denied", message: "Write access is disabled for this characteristic.")
        }

        let characteristic = try characteristic(accessoryID: accessoryID, characteristicID: characteristicID)
        guard characteristic.properties.contains(HMCharacteristicPropertyWritable) else {
            throw APIError(code: "not_writable", message: "HomeKit reports that this characteristic is not writable.")
        }

        try await characteristic.writeValue(value.foundationValue)
        return CharacteristicValue(
            accessoryID: accessoryID,
            characteristicID: characteristicID,
            value: value
        )
    }

    func readCameraMotion(accessoryID: String) async throws -> [CharacteristicValue] {
        let accessory = try permittedAccessory(id: accessoryID)
        let ids = try accessory.cameraMotionReadIDs()
        var readings: [CharacteristicValue] = []
        for id in ids {
            let reading = try await read(accessoryID: accessoryID, characteristicID: id)
            guard case .bool = reading.value else {
                throw APIError(code: "motion_unavailable", message: "HomeKit did not return a Boolean motion state. Try again when the camera is reachable.")
            }
            readings.append(reading)
        }
        return readings
    }

    private func requireAuthorization() throws {
        guard isAuthorized else {
            throw APIError(code: "access_denied", message: "Home access is not authorized.")
        }
    }

    private func jsonValue(for characteristic: HMCharacteristic) throws -> JSONValue {
        if characteristic.metadata?.format == HMCharacteristicMetadataFormatBool,
           let number = characteristic.value as? NSNumber {
            return .bool(number.boolValue)
        }
        return try JSONValue(any: characteristic.value)
    }

    private func characteristic(accessoryID: String, characteristicID: String) throws -> HMCharacteristic {
        guard accessoryIndex[accessoryID] != nil else {
            throw APIError(code: "not_found", message: "Accessory not found.")
        }
        guard let characteristic = characteristicIndex[indexKey(accessoryID, characteristicID)] else {
            throw APIError(code: "not_found", message: "Characteristic not found.")
        }
        return characteristic
    }

    private func rebuildIndex(from homes: [HMHome]) {
        var descriptors: [AccessoryDescriptor] = []
        var newAccessoryIndex: [String: HMAccessory] = [:]
        var newCharacteristicIndex: [String: HMCharacteristic] = [:]

        for home in homes {
            for accessory in home.accessories {
                let accessoryID = accessory.uniqueIdentifier.uuidString.lowercased()
                newAccessoryIndex[accessoryID] = accessory
                let rule = policyStore.document.rules[accessoryID]

                let services = accessory.services.map { service in
                    let serviceID = service.uniqueIdentifier.uuidString.lowercased()
                    let characteristics = service.characteristics.map { characteristic in
                        let characteristicID = characteristic.uniqueIdentifier.uuidString.lowercased()
                        let access = rule?.effectiveAccess(for: characteristicID) ?? .denied
                        newCharacteristicIndex[indexKey(accessoryID, characteristicID)] = characteristic

                        return CharacteristicDescriptor(
                            id: characteristicID,
                            name: characteristic.localizedDescription,
                            type: characteristic.characteristicType,
                            readable: characteristic.properties.contains(HMCharacteristicPropertyReadable),
                            writable: characteristic.properties.contains(HMCharacteristicPropertyWritable),
                            access: access,
                            value: try? jsonValue(for: characteristic)
                        )
                    }

                    return ServiceDescriptor(
                        id: serviceID,
                        name: service.name,
                        type: service.serviceType,
                        characteristics: characteristics
                    )
                }

                let cameraProfiles = accessory.cameraProfiles ?? []
                let camera: CameraDescriptor? = cameraProfiles.isEmpty ? nil : CameraDescriptor(
                    motionCharacteristicIDs: services.flatMap(\.characteristics)
                        .filter { $0.type == HMCharacteristicTypeMotionDetected }
                        .map(\.id)
                )

                descriptors.append(AccessoryDescriptor(
                    id: accessoryID,
                    name: accessory.name,
                    room: accessory.room?.name,
                    category: accessory.category.localizedDescription,
                    reachable: accessory.isReachable,
                    categoryType: accessory.category.categoryType,
                    manufacturer: accessory.manufacturer,
                    model: accessory.model,
                    firmwareVersion: accessory.firmwareVersion,
                    access: rule?.access ?? .denied,
                    camera: camera,
                    services: services
                ))
            }
        }

        accessoryIndex = newAccessoryIndex
        characteristicIndex = newCharacteristicIndex
        accessories = descriptors.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func indexKey(_ accessoryID: String, _ characteristicID: String) -> String {
        "\(accessoryID):\(characteristicID)"
    }
}
