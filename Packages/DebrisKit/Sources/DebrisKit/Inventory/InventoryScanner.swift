import Foundation

public actor InventoryScanner {
    public struct Options: Sendable {
        public var roots: [URL]
        public var useSpotlight: Bool
        public var readSigning: Bool
        public var maxDepth: Int
        public var homebrewPrefixes: [URL]

        public init(roots: [URL], useSpotlight: Bool = true, readSigning: Bool = true,
                    maxDepth: Int = 12, homebrewPrefixes: [URL]) {
            self.roots = roots
            self.useSpotlight = useSpotlight
            self.readSigning = readSigning
            self.maxDepth = maxDepth
            self.homebrewPrefixes = homebrewPrefixes
        }

        public static func standard(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Options {
            let roots = [
                "/Applications",
                "/System/Applications",
                "/System/Library/CoreServices",
                "/Library/Application Support",
                "/Library/PreferencePanes",
                "/Library/Screen Savers",
                "/Library/QuickLook",
                "/Library/Internet Plug-Ins",
                "/Library/Input Methods",
                "/Library/Audio/Plug-Ins",
                "/Library/Frameworks",
                "/Library/Extensions",
                "/opt/homebrew/Caskroom",
                "/usr/local/Caskroom",
            ].map { URL(fileURLWithPath: $0) } + [
                home.appendingPathComponent("Applications"),
                home.appendingPathComponent("Library/Application Support"),
                home.appendingPathComponent("Library/Screen Savers"),
                home.appendingPathComponent("Library/QuickLook"),
                home.appendingPathComponent("Library/Audio/Plug-Ins"),
                home.appendingPathComponent("Library/PreferencePanes"),
            ]
            let prefixes = ["/opt/homebrew", "/usr/local"].map { URL(fileURLWithPath: $0) }
            return Options(roots: roots, homebrewPrefixes: prefixes)
        }
    }

    static let prunedDirectoryNames: Set<String> = [
        "node_modules", ".git", "site-packages", "DerivedData", "CoreSimulator", "Caches",
        "Cache", "__pycache__", "Xcode", "Cellar", "Homebrew",
    ]

    private let options: Options

    public init(options: Options = .standard()) {
        self.options = options
    }

    public func scan(progress: (@Sendable (ScanProgress) -> Void)? = nil) async -> AppInventory {
        var found: [String: InstalledApp] = [:]
        let roots = options.roots.filter { FileManager.default.fileExists(atPath: $0.path) }
        for (index, root) in roots.enumerated() {
            progress?(ScanProgress(phase: "Reading \(root.path)", completed: index, total: roots.count + 1))
            for app in walk(root, maxDepth: options.maxDepth, readSigning: options.readSigning) where found[app.url.path] == nil {
                found[app.url.path] = app
            }
            await Task.yield()
        }
        if options.useSpotlight {
            progress?(ScanProgress(phase: "Asking Spotlight", completed: roots.count, total: roots.count + 1))
            for url in spotlightApplications() where found[url.path] == nil {
                if let app = makeApp(at: url, infoAt: url, source: .other, readSigning: false) {
                    found[url.path] = app
                }
            }
        }
        let formulae = homebrewFormulae(prefixes: options.homebrewPrefixes)
        progress?(ScanProgress(phase: "Done", completed: roots.count + 1, total: roots.count + 1))
        return AppInventory(apps: Array(found.values), homebrewFormulae: formulae)
    }

    // MARK: - Walking

    private nonisolated func walk(_ root: URL, maxDepth: Int, readSigning: Bool) -> [InstalledApp] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles], errorHandler: { _, _ in true }
        ) else { return [] }

        var apps: [InstalledApp] = []
        var enclosingApps: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isDirectory == true, values.isSymbolicLink != true
            else { continue }
            let name = url.lastPathComponent
            if Self.prunedDirectoryNames.contains(name) || enumerator.level > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            let ext = url.pathExtension.lowercased()
            guard BundleReader.bundleExtensions.contains(ext) else { continue }

            // iOS apps installed on a Mac keep the real bundle at Outer.app/Wrapper/Inner.app
            var bundleURL = url
            let parent = url.deletingLastPathComponent()
            if parent.lastPathComponent == "Wrapper", parent.deletingLastPathComponent().pathExtension == "app" {
                bundleURL = parent.deletingLastPathComponent()
            }
            while let last = enclosingApps.last, !bundleURL.path.hasPrefix(last.path + "/") {
                enclosingApps.removeLast()
            }
            let embedded = !enclosingApps.isEmpty
            let source: InstalledApp.Source = embedded ? .embedded : sourceFor(root: root, url: bundleURL)
            if let app = makeApp(at: bundleURL, infoAt: url, source: source, readSigning: readSigning && !embedded) {
                apps.append(app)
                if ext == "app" { enclosingApps.append(bundleURL) }
            }
        }
        return apps
    }

    private nonisolated func sourceFor(root: URL, url: URL) -> InstalledApp.Source {
        let path = root.path
        if path == "/Applications" { return .applications }
        if path.hasSuffix("/Applications") { return .userApplications }
        if path.hasPrefix("/System") { return .system }
        if path.hasSuffix("/Caskroom") {
            let relative = url.path.dropFirst(path.count + 1)
            if let cask = relative.split(separator: "/").first { return .homebrewCask(String(cask)) }
        }
        return .other
    }

    private nonisolated func makeApp(at url: URL, infoAt infoURL: URL, source: InstalledApp.Source, readSigning: Bool) -> InstalledApp? {
        guard let info = BundleReader.info(at: infoURL) else { return nil }
        let signing = readSigning ? BundleReader.signing(at: url) : BundleReader.Signing(teamID: nil, appGroups: [])
        return InstalledApp(bundleID: info.bundleID, name: info.name, url: url, version: info.version,
                            teamID: signing.teamID, appGroups: signing.appGroups, source: source)
    }

    // MARK: - Other sources

    private nonisolated func spotlightApplications() -> [URL] {
        guard let output = try? Shell.run("/usr/bin/mdfind", ["kMDItemContentType == 'com.apple.application-bundle'"], timeout: 20) else {
            return []
        }
        return output.split(separator: "\n").map(String.init).filter { path in
            !path.hasPrefix("/Volumes/") && !path.contains("/.Trash/") && !path.contains("/CoreSimulator/")
                && !path.contains("/DerivedData/") && !path.hasPrefix("/private/var/folders/")
        }.map { URL(fileURLWithPath: $0) }
    }

    private nonisolated func homebrewFormulae(prefixes: [URL]) -> Set<String> {
        var names = Set<String>()
        for prefix in prefixes {
            for sub in ["Cellar", "Caskroom"] {
                let dir = prefix.appendingPathComponent(sub)
                if let entries = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
                    for entry in entries where !entry.hasPrefix(".") { names.insert(entry) }
                }
            }
        }
        return names
    }
}
