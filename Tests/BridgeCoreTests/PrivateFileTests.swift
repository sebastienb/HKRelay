import Foundation
import Testing
@testable import BridgeCore

@Test func privateFileReplacesPublicFileAndSymlinkPrivately() throws {
    let files = FileManager.default
    let directory = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try files.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? files.removeItem(at: directory) }
    try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
    let target = directory.appendingPathComponent("credentials.json")
    try Data("old".utf8).write(to: target)
    try files.setAttributes([.posixPermissions: 0o644], ofItemAtPath: target.path)
    try PrivateFile.write(Data("new".utf8), to: target)
    #expect(try Data(contentsOf: target) == Data("new".utf8))
    #expect((try files.attributesOfItem(atPath: target.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)

    let outside = directory.appendingPathComponent("untouched")
    try Data("untouched".utf8).write(to: outside)
    try files.removeItem(at: target)
    try files.createSymbolicLink(at: target, withDestinationURL: outside)
    try PrivateFile.write(Data("private".utf8), to: target)
    #expect(try Data(contentsOf: outside) == Data("untouched".utf8))
    #expect(try Data(contentsOf: target) == Data("private".utf8))
    #expect((try files.contentsOfDirectory(atPath: directory.path)).sorted() == ["credentials.json", "untouched"])

    // Reject a directory another local account could modify.
    try files.setAttributes([.posixPermissions: 0o777], ofItemAtPath: directory.path)
    #expect(throws: POSIXError(.EACCES)) {
        try PrivateFile.write(Data("rejected".utf8), to: target)
    }
    #expect(try Data(contentsOf: target) == Data("private".utf8))
}

@Test func privateFileCleansUpFailedReplacement() throws {
    let files = FileManager.default
    let directory = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let target = directory.appendingPathComponent("directory")
    try files.createDirectory(at: target, withIntermediateDirectories: true)
    defer { try? files.removeItem(at: directory) }
    #expect(throws: (any Error).self) { try PrivateFile.write(Data("secret".utf8), to: target) }
    #expect(try files.contentsOfDirectory(atPath: directory.path) == ["directory"])
}
