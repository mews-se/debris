import Foundation

public struct LeftoverLocation: Sendable, Hashable, Identifiable {
    public enum Domain: Sendable, Hashable {
        case user
        case system
    }

    public enum Kind: String, Sendable, Hashable, CaseIterable {
        case application = "Application"
        case applicationSupport = "Application Support"
        case caches = "Caches"
        case preferences = "Preferences"
        case containers = "Containers"
        case groupContainers = "Group Containers"
        case applicationScripts = "Application Scripts"
        case savedState = "Saved Application State"
        case httpStorages = "HTTP Storages"
        case webKit = "WebKit"
        case cookies = "Cookies"
        case logs = "Logs"
        case launchAgents = "Launch Agents"
        case launchDaemons = "Launch Daemons"
        case privilegedHelpers = "Privileged Helper Tools"
        case kernelExtensions = "Kernel Extensions"
        case systemExtensions = "System Extensions"
        case audioPlugins = "Audio Plug-Ins"
        case frameworks = "Frameworks"
        case screenSavers = "Screen Savers"
        case quickLook = "QuickLook"
        case preferencePanes = "Preference Panes"
        case services = "Services"
        case internetPlugins = "Internet Plug-Ins"
        case binaries = "Command line tools"
        case receipts = "Package receipts"
        case shared = "Shared"
        case dotfiles = "Home folder dotfiles"
        case config = "~/.config"
        case localShare = "~/.local/share"
        case userCache = "~/.cache"
        case developer = "Developer"
        case toolCache = "Tool caches"
        case downloads = "Downloads"
    }

    public let kind: Kind
    public let domain: Domain
    public let url: URL

    public init(kind: Kind, domain: Domain, url: URL) {
        self.kind = kind
        self.domain = domain
        self.url = url
    }

    public var id: String { url.path }
    public var title: String { kind.rawValue }
    public var isDotfileArea: Bool { [.dotfiles, .config, .localShare, .userCache].contains(kind) }
}

public enum LocationCatalog {
    public static func standard(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [LeftoverLocation] {
        let lib = home.appendingPathComponent("Library")
        func user(_ kind: LeftoverLocation.Kind, _ path: String) -> LeftoverLocation {
            LeftoverLocation(kind: kind, domain: .user, url: lib.appendingPathComponent(path))
        }
        func system(_ kind: LeftoverLocation.Kind, _ path: String) -> LeftoverLocation {
            LeftoverLocation(kind: kind, domain: .system, url: URL(fileURLWithPath: path))
        }
        return [
            user(.applicationSupport, "Application Support"),
            user(.caches, "Caches"),
            user(.preferences, "Preferences"),
            user(.preferences, "Preferences/ByHost"),
            user(.containers, "Containers"),
            user(.groupContainers, "Group Containers"),
            user(.applicationScripts, "Application Scripts"),
            user(.savedState, "Saved Application State"),
            user(.httpStorages, "HTTPStorages"),
            user(.webKit, "WebKit"),
            user(.cookies, "Cookies"),
            user(.logs, "Logs"),
            user(.launchAgents, "LaunchAgents"),
            user(.audioPlugins, "Audio/Plug-Ins/Components"),
            user(.audioPlugins, "Audio/Plug-Ins/VST"),
            user(.audioPlugins, "Audio/Plug-Ins/VST3"),
            user(.screenSavers, "Screen Savers"),
            user(.quickLook, "QuickLook"),
            user(.preferencePanes, "PreferencePanes"),
            user(.services, "Services"),
            user(.internetPlugins, "Internet Plug-Ins"),
            LeftoverLocation(kind: .dotfiles, domain: .user, url: home),
            LeftoverLocation(kind: .config, domain: .user, url: home.appendingPathComponent(".config")),
            LeftoverLocation(kind: .localShare, domain: .user, url: home.appendingPathComponent(".local/share")),
            LeftoverLocation(kind: .userCache, domain: .user, url: home.appendingPathComponent(".cache")),
            LeftoverLocation(kind: .shared, domain: .user, url: URL(fileURLWithPath: "/Users/Shared")),
            system(.applicationSupport, "/Library/Application Support"),
            system(.caches, "/Library/Caches"),
            system(.preferences, "/Library/Preferences"),
            system(.launchAgents, "/Library/LaunchAgents"),
            system(.launchDaemons, "/Library/LaunchDaemons"),
            system(.privilegedHelpers, "/Library/PrivilegedHelperTools"),
            system(.kernelExtensions, "/Library/Extensions"),
            system(.systemExtensions, "/Library/SystemExtensions"),
            system(.audioPlugins, "/Library/Audio/Plug-Ins/HAL"),
            system(.audioPlugins, "/Library/Audio/Plug-Ins/Components"),
            system(.audioPlugins, "/Library/Audio/Plug-Ins/VST"),
            system(.audioPlugins, "/Library/Audio/Plug-Ins/VST3"),
            system(.frameworks, "/Library/Frameworks"),
            system(.screenSavers, "/Library/Screen Savers"),
            system(.quickLook, "/Library/QuickLook"),
            system(.preferencePanes, "/Library/PreferencePanes"),
            system(.internetPlugins, "/Library/Internet Plug-Ins"),
            system(.logs, "/Library/Logs"),
            system(.binaries, "/usr/local/bin"),
        ]
    }
}
