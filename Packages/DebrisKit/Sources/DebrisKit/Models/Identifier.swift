import Foundation

public enum Identifier {
    static let groupingHosts: Set<String> = ["github", "gitlab", "sourceforge", "googlecode", "bitbucket"]

    /// "com.microsoft.Outlook" -> "com.microsoft"; "io.github.alice.tool" -> "io.github.alice"
    public static func vendor(of bundleID: String) -> String {
        let parts = bundleID.lowercased().split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return bundleID.lowercased() }
        if parts.count >= 3, groupingHosts.contains(parts[1]) {
            return parts[0...2].joined(separator: ".")
        }
        return parts[0...1].joined(separator: ".")
    }

    public static func components(of bundleID: String) -> [String] {
        bundleID.lowercased().split(separator: ".").map(String.init)
    }

    /// Lowercased letters and digits only, for fuzzy name comparison.
    public static func normalized(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII })
    }
}
