import Foundation

public enum IdentifierParser {
    static let strippedSuffixes = [".plist", ".savedState", ".binarycookies", ".sfl2", ".sfl3", ".log", ".db", ".sqlite", ".sqlite3", ".json"]
    static let firstComponents: Set<String> = [
        "com", "org", "net", "io", "se", "de", "uk", "co", "us", "dev", "app", "fr", "nl", "ch", "at",
        "eu", "info", "me", "tv", "cc", "ru", "ca", "jp", "xyz", "ai", "sh", "fm", "pl", "it", "es", "no",
        "fi", "dk", "be", "cz", "ly", "ee", "is", "nu", "md", "st", "so", "to", "design", "studio",
        "software", "tech", "group", "systems", "codes", "gg", "zone", "team", "tools", "one", "cn",
        "kr", "tw", "in", "br", "au", "nz", "pro", "site", "pw", "edu", "gov", "ovh", "re", "im",
        "oss", "desktop", "ws", "biz", "name", "mobi", "cloud", "page", "run", "live", "chat",
    ]

    /// Derives a reverse-DNS identifier from a file or folder name, or nil when the name is not one.
    /// "ABCDE12345.com.foo.Bar" -> "com.foo.Bar", "group.com.foo.Bar.plist" -> "com.foo.Bar".
    public static func identifier(fromName name: String) -> String? {
        var base = name
        for suffix in strippedSuffixes where base.hasSuffix(suffix) {
            base = String(base.dropLast(suffix.count))
        }
        guard !base.hasPrefix("."), base.contains(".") else { return nil }
        base = stripContainerPrefixes(base)

        // Trailing ByHost UUID, e.g. com.foo.Bar.4D2AF975-BCF7-5E24-BFBF-30874BB84083
        if let range = base.range(of: #"\.[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"#, options: .regularExpression) {
            base = String(base[..<range.lowerBound])
        }

        let parts = base.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        let validPart = #"^[A-Za-z0-9_\-+ ]+$"#
        guard parts.allSatisfy({ $0.range(of: validPart, options: .regularExpression) != nil }) else { return nil }
        let first = parts[0].lowercased()
        if firstComponents.contains(first) { return base }
        if parts.count >= 3, first.count <= 6, first.allSatisfy(\.isLetter) { return base }
        return nil
    }

    /// Team IDs and group markers can appear in either order: "group.TEAMID.com.foo" or "TEAMID.group.com.foo".
    static func stripContainerPrefixes(_ name: String) -> String {
        var base = name
        var changed = true
        while changed {
            changed = false
            if let range = base.range(of: #"^[A-Z0-9]{10}\."#, options: .regularExpression) {
                base = String(base[range.upperBound...]); changed = true
            }
            for marker in ["group.", "groups.", "maccatalyst."] where base.hasPrefix(marker) {
                base = String(base.dropFirst(marker.count)); changed = true
            }
        }
        return base
    }

    /// "UBF8T346G9.Office" -> "UBF8T346G9"
    public static func teamPrefix(of name: String) -> String? {
        var base = name
        for marker in ["group.", "groups."] where base.hasPrefix(marker) { base = String(base.dropFirst(marker.count)) }
        guard let range = base.range(of: #"^[A-Z0-9]{10}\."#, options: .regularExpression) else { return nil }
        return String(base[base.startIndex..<base.index(before: range.upperBound)])
    }

    /// The app-group form of a name as it appears in entitlements: team prefix removed, "group." kept.
    public static func appGroupName(of name: String) -> String {
        var base = name
        if let range = base.range(of: #"^[A-Z0-9]{10}\."#, options: .regularExpression) {
            base = String(base[range.upperBound...])
        }
        return base
    }

    public static func isUUIDName(_ name: String) -> Bool {
        name.range(of: #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"#, options: .regularExpression) != nil
    }

    /// Name components worth matching against installed apps: "com.macpaw.CleanMyMac4" -> ["macpaw", "cleanmymac4"]
    public static func nameParts(of identifier: String) -> [String] {
        let parts = Identifier.components(of: identifier)
        guard parts.count >= 2 else { return [] }
        return Array(parts.dropFirst()).map(Identifier.normalized).filter { $0.count >= 4 }
    }
}
