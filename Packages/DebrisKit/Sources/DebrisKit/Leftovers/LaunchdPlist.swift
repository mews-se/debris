import Foundation

enum LaunchdPlist {
    /// Bundle identifiers a launchd job declares or implies: AssociatedBundleIdentifiers, plus the
    /// bundle that contains its program when the program lives inside an .app.
    static func associatedBundleIDs(at url: URL) -> [String]? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        var ids: [String] = []
        if let list = plist["AssociatedBundleIdentifiers"] as? [String] { ids += list }
        if let single = plist["AssociatedBundleIdentifiers"] as? String { ids.append(single) }
        var program = plist["Program"] as? String
        if program == nil, let arguments = plist["ProgramArguments"] as? [String] { program = arguments.first }
        if let program, let range = program.range(of: #"^(.*?\.app)/"#, options: .regularExpression) {
            let appPath = String(program[range.lowerBound..<program.index(before: range.upperBound)])
            if let info = BundleReader.info(at: URL(fileURLWithPath: appPath)) { ids.append(info.bundleID) }
        }
        return ids.isEmpty ? nil : ids
    }
}
