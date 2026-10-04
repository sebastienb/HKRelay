import Foundation

public struct APIError: Codable, Error, Equatable, Sendable {
    public var code: String
    public var message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct APIEnvelope: Codable, Equatable, Sendable {
    public var ok: Bool
    public var data: JSONValue?
    public var error: APIError?

    public init(ok: Bool, data: JSONValue? = nil, error: APIError? = nil) {
        self.ok = ok
        self.data = data
        self.error = error
    }

    public static func success(_ data: JSONValue? = nil) -> APIEnvelope {
        APIEnvelope(ok: true, data: data)
    }

    public static func failure(code: String, message: String) -> APIEnvelope {
        APIEnvelope(ok: false, error: APIError(code: code, message: message))
    }
}

public struct BridgeStatus: Codable, Equatable, Sendable {
    public var version: String
    public var homeKitAuthorized: Bool
    public var homeDataLoaded: Bool
    public var loopbackOnly: Bool
    public var authenticationRequired: Bool

    public init(
        version: String,
        homeKitAuthorized: Bool,
        homeDataLoaded: Bool,
        loopbackOnly: Bool = true,
        authenticationRequired: Bool = true
    ) {
        self.version = version
        self.homeKitAuthorized = homeKitAuthorized
        self.homeDataLoaded = homeDataLoaded
        self.loopbackOnly = loopbackOnly
        self.authenticationRequired = authenticationRequired
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        homeKitAuthorized = try container.decode(Bool.self, forKey: .homeKitAuthorized)
        homeDataLoaded = try container.decode(Bool.self, forKey: .homeDataLoaded)
        loopbackOnly = try container.decodeIfPresent(Bool.self, forKey: .loopbackOnly) ?? true
        authenticationRequired = try container.decodeIfPresent(Bool.self, forKey: .authenticationRequired) ?? true
    }
}

public struct CameraDescriptor: Codable, Equatable, Sendable {
    public var motionCharacteristicIDs: [String]

    public init(motionCharacteristicIDs: [String]) {
        self.motionCharacteristicIDs = motionCharacteristicIDs
    }
}

public struct AccessoryDescriptor: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var room: String?
    public var category: String
    public var categoryType: String?
    public var manufacturer: String?
    public var model: String?
    public var firmwareVersion: String?
    public var reachable: Bool
    public var access: AccessLevel
    public var camera: CameraDescriptor?
    public var services: [ServiceDescriptor]

    public init(
        id: String,
        name: String,
        room: String? = nil,
        category: String,
        reachable: Bool,
        categoryType: String? = nil,
        manufacturer: String? = nil,
        model: String? = nil,
        firmwareVersion: String? = nil,
        access: AccessLevel = .denied,
        camera: CameraDescriptor? = nil,
        services: [ServiceDescriptor] = []
    ) {
        self.id = id
        self.name = name
        self.room = room
        self.category = category
        self.categoryType = categoryType
        self.manufacturer = manufacturer
        self.model = model
        self.firmwareVersion = firmwareVersion
        self.reachable = reachable
        self.access = access
        self.camera = camera
        self.services = services
    }
}

extension AccessoryDescriptor {
    /// Discovery must not expose cached values, including denied characteristics.
    public var discoverySnapshot: AccessoryDescriptor {
        var copy = self
        copy.services = services.map { service in
            var service = service
            service.characteristics = service.characteristics.map { characteristic in
                var characteristic = characteristic
                characteristic.value = nil
                return characteristic
            }
            return service
        }
        return copy
    }

    /// Validate every sensor before starting any HomeKit reads.
    public func cameraMotionReadIDs() throws -> [String] {
        guard access != .denied else {
            throw APIError(code: "access_denied", message: "This accessory is not exposed by the bridge.")
        }
        guard let camera else {
            throw APIError(code: "camera_unsupported", message: "This accessory does not have a camera.")
        }
        guard !camera.motionCharacteristicIDs.isEmpty else {
            throw APIError(code: "motion_unsupported", message: "This camera exposes no HomeKit motion characteristic.")
        }
        let characteristics = services.flatMap(\.characteristics)
        for id in camera.motionCharacteristicIDs {
            guard let characteristic = characteristics.first(where: { $0.id == id }) else {
                throw APIError(code: "not_found", message: "Motion characteristic not found.")
            }
            guard characteristic.access.allowsRead else {
                throw APIError(code: "read_denied", message: "Read access is disabled for a motion characteristic.")
            }
            guard characteristic.readable else {
                throw APIError(code: "not_readable", message: "HomeKit reports that a motion characteristic is not readable.")
            }
        }
        return camera.motionCharacteristicIDs
    }
}

public struct ServiceDescriptor: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var type: String
    public var characteristics: [CharacteristicDescriptor]

    public init(
        id: String,
        name: String,
        type: String,
        characteristics: [CharacteristicDescriptor] = []
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.characteristics = characteristics
    }
}

public struct CharacteristicDescriptor: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var type: String
    public var readable: Bool
    public var writable: Bool
    public var access: AccessLevel
    public var value: JSONValue?

    public init(
        id: String,
        name: String,
        type: String,
        readable: Bool,
        writable: Bool,
        access: AccessLevel = .denied,
        value: JSONValue? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.readable = readable
        self.writable = writable
        self.access = access
        self.value = value
    }
}

public struct CharacteristicValue: Codable, Equatable, Sendable {
    public var accessoryID: String
    public var characteristicID: String
    public var value: JSONValue

    public init(accessoryID: String, characteristicID: String, value: JSONValue) {
        self.accessoryID = accessoryID
        self.characteristicID = characteristicID
        self.value = value
    }
}
