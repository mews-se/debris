import Foundation
import Testing
@testable import DebrisKit

/// Runs the generated script as the current user against a scratch folder. Root-only steps
/// (launchctl, noschg) are no-ops there, the moving and naming logic is the same.
struct AdminRemoverTests {
    func scratch() throws -> (root: URL, trash: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("debris-admin-\(UUID().uuidString)")
        let trash = root.appendingPathComponent("Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        return (root, trash)
    }

    func run(_ script: String) throws -> String {
        try Shell.run("/bin/bash", ["-c", script], timeout: 30)
    }

    @Test func movesLockedFilesAndKeepsNamesUnique() throws {
        let (root, trash) = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let locked = root.appendingPathComponent("it's locked.plist")
        try Data("a".utf8).write(to: locked)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: locked.path)
        let folder = root.appendingPathComponent("Helper")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("b".utf8).write(to: folder.appendingPathComponent("inner"))
        try FileManager.default.createDirectory(at: trash.appendingPathComponent("Helper"), withIntermediateDirectories: true)
        let missing = root.appendingPathComponent("gone")

        let script = AdminRemover.script(for: [locked, folder, missing], trash: trash, uid: getuid(), gid: getgid())
        let results = AdminRemover.results(from: try run(script), for: [locked, folder, missing])

        #expect(results[0].succeeded)
        #expect(results[1].succeeded)
        #expect(!results[2].succeeded)
        #expect(!FileManager.default.fileExists(atPath: locked.path))
        #expect(FileManager.default.fileExists(atPath: trash.appendingPathComponent("it's locked.plist").path))
        if case .trashed(let moved) = results[1].outcome {
            #expect(moved.lastPathComponent != "Helper", "a name already in the Trash gets a time stamp")
            #expect(FileManager.default.fileExists(atPath: moved.appendingPathComponent("inner").path))
        }
    }

    @Test func reportsEveryPathEvenWhenOutputIsShort() {
        let urls = [URL(fileURLWithPath: "/Library/LaunchDaemons/a.plist"), URL(fileURLWithPath: "/Library/PrivilegedHelperTools/b")]
        let results = AdminRemover.results(from: "OK\t/Library/LaunchDaemons/a.plist\t/Users/x/.Trash/a.plist\n", for: urls)
        #expect(results[0].succeeded)
        #expect(!results[1].succeeded)
    }
}
