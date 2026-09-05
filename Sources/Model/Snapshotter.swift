import AppKit
import SwiftUI

/// Development aid: `Debris -snapshotDir /some/dir` walks through the modules, writes a PNG of
/// the window for each, and quits. Rendering goes through the view hierarchy, so it needs no
/// screen recording permission; vibrancy and sidebar materials do not survive the trip.
@MainActor
enum Snapshotter {
    static var directory: URL? {
        UserDefaults.standard.string(forKey: "snapshotDir").map { URL(fileURLWithPath: $0) }
    }

    static func runIfRequested(model: AppModel) {
        guard let directory else { return }
        Task { await run(model: model, into: directory) }
    }

    private static func run(model: AppModel, into directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        while !model.hasInventory { try? await Task.sleep(for: .milliseconds(200)) }
        try? await Task.sleep(for: .seconds(1))
        capture("1-leftovers-intro", into: directory)

        await model.leftovers.scan(inventory: model.inventory)
        try? await Task.sleep(for: .seconds(1))
        capture("2-leftovers-results", into: directory)

        model.leftovers.minimumConfidence = .low
        try? await Task.sleep(for: .seconds(1))
        capture("3-leftovers-everything", into: directory)

        model.module = .uninstall
        try? await Task.sleep(for: .seconds(1))
        capture("4-uninstall", into: directory)

        model.module = .clean
        try? await Task.sleep(for: .seconds(1))
        capture("5-clean", into: directory)
        NSApp.terminate(nil)
    }

    private static func capture(_ name: String, into directory: URL) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
        let file = directory.appendingPathComponent("\(name).png")
        guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: file)
    }
}
