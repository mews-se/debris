import Foundation
import Testing
@testable import DebrisKit

struct FullDiskAccessTests {
    @Test func missingProbesDoNotCountAsAccess() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("debris-fda-\(UUID().uuidString)")
        #expect(!FullDiskAccess.isGranted(probes: [root.appendingPathComponent("TCC.db"), root.appendingPathComponent("Safari")]))
    }

    @Test func anyReadableProbeIsEnough() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("debris-fda-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Safari")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("TCC.db")
        try Data("x".utf8).write(to: file)

        #expect(FullDiskAccess.isGranted(probes: [root.appendingPathComponent("gone.db"), folder]))
        #expect(FullDiskAccess.isGranted(probes: [root.appendingPathComponent("gone.db"), file]))
    }
}
