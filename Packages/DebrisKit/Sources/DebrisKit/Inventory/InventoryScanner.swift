import Foundation

public actor InventoryScanner {
    public struct Options: Sendable {
        public var roots: [URL]
        public var useSpotlight: Bool
        public var readSigning: Bool
        public var maxDepth: Int
        public var homebrewPrefixes: [URL]
        public var commandDirectories: [URL]

        public init(roots: [URL], useSpotlight: Bool = true, readSigning: Bool = true,
                    maxDepth: Int = 12, homebrewPrefixes: [URL], commandDirectories: [URL] = []) {
            self.roots = roots
            self.useSpotlight = useSpotlight
            self.readSigning = readSigning
            self.maxDepth = maxDepth
            self.homebrewPrefixes = homebrewPrefixes
            self.commandDirectories = commandDirectories
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
            let commandDirectories = [
                "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/local/sbin",
            ].map { URL(fileURLWithPath: $0) } + [
                home.appendingPathComponent(".local/bin"),
                home.appendingPathComponent(".cargo/bin"),
                home.appendingPathComponent("go/bin"),
                home.appendingPathComponent("bin"),
            ]
            return Options(roots: roots, homebrewPrefixes: prefixes, commandDirectories: commandDirectories)
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
        let commands = commandNames(in: options.commandDirectories)
        progress?(ScanProgress(phase: "Done", completed: roots.count + 1, total: roots.count + 1))
        return AppInventory(apps: Array(found.values), homebrewFormulae: formulae, commands: commands)
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
            while let last = enclosingApps.last, !url.path.hasPrefix(last.path + "/") {
                enclosingApps.removeLast()
            }
            if enumerator.level > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            if Self.prunedDirectoryNames.contains(url.lastPathComponent) {
                // Electron apps ship whole apps under node_modules, so inside a bundle the
                // pruned tree is still read, with readdir rather than the enumerator
                if !enclosingApps.isEmpty {
                    for bundle in bundles(under: url, maxDepth: maxDepth - enumerator.level) {
                        if let app = makeApp(at: bundle, infoAt: bundle, source: .embedded, readSigning: false) {
                            apps.append(app)
                        }
                    }
                }
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
            let embedded = !enclosingApps.isEmpty
            let source: InstalledApp.Source = embedded ? .embedded : sourceFor(root: root, url: bundleURL)
            if let app = makeApp(at: bundleURL, infoAt: url, source: source, readSigning: readSigning && !embedded) {
                apps.append(app)
                if ext == "app" { enclosingApps.append(bundleURL) }
            }
        }
        return apps
    }

    /// Directories with a bundle extension below `root`. readdir gives the type of each entry
    /// without a URL or an attribute lookup, so tens of thousands of files cost milliseconds.
    private nonisolated func bundles(under root: URL, maxDepth: Int) -> [URL] {
        var found: [URL] = []
        func visit(_ path: String, depth: Int) {
            guard depth <= maxDepth, let dir = opendir(path) else { return }
            defer { closedir(dir) }
            while let entry = readdir(dir) {
                guard Int32(entry.pointee.d_type) == DT_DIR else { continue }
                let name = withUnsafeBytes(of: entry.pointee.d_name) {
                    String(decoding: $0.prefix(Int(entry.pointee.d_namlen)), as: UTF8.self)
                }
                if name.hasPrefix(".") { continue }
                let child = path + "/" + name
                if BundleReader.bundleExtensions.contains((name as NSString).pathExtension.lowercased()) {
                    found.append(URL(fileURLWithPath: child, isDirectory: true))
                }
                visit(child, depth: depth + 1)
            }
        }
        visit(root.path, depth: 1)
        return found
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

    private nonisolated func commandNames(in directories: [URL]) -> Set<String> {
        var names = Set<String>()
        for directory in directories {
            if let entries = try? FileManager.default.contentsOfDirectory(atPath: directory.path) {
                for entry in entries where !entry.hasPrefix(".") { names.insert(entry) }
            }
        }
        return names
    }
}
