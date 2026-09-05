import Foundation
import Security

enum BundleReader {
    static let bundleExtensions: Set<String> = [
        "app", "appex", "xpc", "framework", "driver", "kext", "saver", "qlgenerator",
        "plugin", "bundle", "prefpane", "systemextension", "dext", "component", "vst", "vst3",
    ]

    struct Info {
        var bundleID: String
        var name: String
        var version: String?
    }

    static func info(at url: URL) -> Info? {
        let candidates = [
            url.appendingPathComponent("Contents/Info.plist"),
            url.appendingPathComponent("Info.plist"),
        ]
        for plistURL in candidates {
            guard let data = try? Data(contentsOf: plistURL),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let bundleID = plist["CFBundleIdentifier"] as? String, !bundleID.isEmpty
            else { continue }
            let name = (plist["CFBundleDisplayName"] as? String)
                ?? (plist["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent
            let version = (plist["CFBundleShortVersionString"] as? String) ?? (plist["CFBundleVersion"] as? String)
            return Info(bundleID: bundleID, name: name, version: version)
        }
        return nil
    }

    struct Signing {
        var teamID: String?
        var appGroups: [String]
    }

    static func signing(at url: URL) -> Signing {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
            return Signing(teamID: nil, appGroups: [])
        }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess,
              let dict = info as? [String: Any]
        else { return Signing(teamID: nil, appGroups: []) }
        let team = dict[kSecCodeInfoTeamIdentifier as String] as? String
        let entitlements = dict[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        let groups = entitlements?["com.apple.security.application-groups"] as? [String] ?? []
        return Signing(teamID: team, appGroups: groups)
    }
}
