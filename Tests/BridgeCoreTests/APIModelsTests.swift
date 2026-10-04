import Foundation
import Testing
@testable import BridgeCore

@Suite("API models")
struct APIModelsTests {
    @Test("Accessory category type round-trips through Codable")
    func accessoryCategoryTypeRoundTrip() throws {
        let original = AccessoryDescriptor(
            id: "mock-light",
            name: "Mock Light",
            room: "Living Room",
            category: "Lightbulb",
            reachable: true,
            categoryType: "public.hap.category.lightbulb",
            manufacturer: "Example Co.",
            model: "Light 2",
            firmwareVersion: "1.2.3",
            access: .readOnly
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AccessoryDescriptor.self, from: data)

        #expect(decoded == original)
    }

    @Test("Older accessory JSON can omit the category type")
    func missingAccessoryCategoryType() throws {
        let data = Data(#"{"id":"mock-light","name":"Mock Light","category":"Lightbulb","reachable":true,"access":"denied","services":[]}"#.utf8)
        let decoded = try JSONDecoder().decode(AccessoryDescriptor.self, from: data)

        #expect(decoded.categoryType == nil)
        #expect(decoded.manufacturer == nil)
        #expect(decoded.model == nil)
        #expect(decoded.firmwareVersion == nil)
    }

    @Test("Camera capabilities round-trip through Codable")
    func cameraDescriptorRoundTrip() throws {
        let original = AccessoryDescriptor(
            id: "mock-camera",
            name: "Mock Camera",
            category: "Camera",
            reachable: true,
            access: .readOnly,
            camera: CameraDescriptor(motionCharacteristicIDs: ["motion-1", "motion-2"])
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AccessoryDescriptor.self, from: data)

        #expect(decoded == original)
        #expect(decoded.camera?.motionCharacteristicIDs == ["motion-1", "motion-2"])
    }

    @Test("Older accessory JSON can omit the camera object")
    func missingCameraDescriptor() throws {
        let data = Data(#"{"id":"mock-light","name":"Mock Light","category":"Lightbulb","reachable":true,"access":"denied","services":[]}"#.utf8)
        let decoded = try JSONDecoder().decode(AccessoryDescriptor.self, from: data)

        #expect(decoded.camera == nil)
    }

    @Test("Camera motion validates all sensors and preserves their IDs")
    func cameraMotionReadIDs() throws {
        var camera = motionCamera()
        #expect(try camera.cameraMotionReadIDs() == ["motion-1", "motion-2"])
        camera.services[0].characteristics[1].access = .denied
        #expect(throws: APIError(code: "read_denied", message: "Read access is disabled for a motion characteristic.")) {
            try camera.cameraMotionReadIDs()
        }
    }

    @Test("Camera motion rejects denied accessories before exposing capabilities")
    func deniedCameraMotion() {
        var camera = motionCamera()
        camera.access = .denied
        camera.camera = nil
        #expect(throws: APIError(code: "access_denied", message: "This accessory is not exposed by the bridge.")) {
            try camera.cameraMotionReadIDs()
        }
    }

    @Test("Missing or unreadable motion is an error, never a false reading")
    func unavailableCameraMotion() {
        var camera = motionCamera()
        camera.camera = CameraDescriptor(motionCharacteristicIDs: [])
        #expect(throws: APIError(code: "motion_unsupported", message: "This camera exposes no HomeKit motion characteristic.")) {
            try camera.cameraMotionReadIDs()
        }
        camera = motionCamera()
        camera.services[0].characteristics[0].readable = false
        #expect(throws: APIError(code: "not_readable", message: "HomeKit reports that a motion characteristic is not readable.")) {
            try camera.cameraMotionReadIDs()
        }
        camera = motionCamera()
        camera.camera = nil
        #expect(throws: APIError(code: "camera_unsupported", message: "This accessory does not have a camera.")) {
            try camera.cameraMotionReadIDs()
        }
    }

    private func motionCamera() -> AccessoryDescriptor {
        AccessoryDescriptor(
            id: "camera", name: "Camera", category: "Camera", reachable: true,
            access: .readOnly,
            camera: CameraDescriptor(motionCharacteristicIDs: ["motion-1", "motion-2"]),
            services: [ServiceDescriptor(
                id: "sensors", name: "Motion", type: "motion",
                characteristics: ["motion-1", "motion-2"].map {
                    CharacteristicDescriptor(id: $0, name: "Motion detected", type: "motion",
                                             readable: true, writable: false, access: .readOnly)
                }
            )]
        )
    }

    @Test("Older status JSON defaults to secure connection settings")
    func missingStatusSecuritySettings() throws {
        let data = Data(#"{"version":"0.1.0","homeKitAuthorized":true,"homeDataLoaded":true}"#.utf8)
        let decoded = try JSONDecoder().decode(BridgeStatus.self, from: data)

        #expect(decoded.loopbackOnly)
        #expect(decoded.authenticationRequired)
    }
}
