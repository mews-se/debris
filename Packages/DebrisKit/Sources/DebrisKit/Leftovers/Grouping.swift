import Foundation

public enum Grouping {
    public static func key(identifier: String?, name: String) -> String {
        if let identifier { return Identifier.vendor(of: identifier) }
        var base = name
        if base.hasPrefix(".") { base = String(base.dropFirst()) }
        return "name:" + Identifier.normalized(base)
    }

    public static func title(for key: String, items: [LeftoverItem]) -> String {
        if key.hasPrefix("name:") {
            let names = Set(items.map { $0.name.hasPrefix(".") ? String($0.name.dropFirst()) : $0.name })
            return names.sorted().first ?? key
        }
        let parts = key.split(separator: ".").map(String.init)
        let vendorWord = parts.count >= 2 ? parts[1] : key
        let products = Set(items.compactMap { item -> String? in
            guard let id = item.identifier else { return nil }
            let comps = id.split(separator: ".").map(String.init)
            guard comps.count >= 3 else { return nil }
            return comps[2]
        })
        let vendorTitle = vendorWord.prefix(1).uppercased() + vendorWord.dropFirst()
        if products.count == 1, let product = products.first, product.lowercased() != vendorWord {
            return "\(vendorTitle) \(product)"
        }
        return vendorTitle
    }

    public static func groups(from items: [LeftoverItem]) -> [GhostApp] {
        var buckets: [String: [LeftoverItem]] = [:]
        for item in items { buckets[item.groupKey, default: []].append(item) }
        return buckets.map { key, items in
            GhostApp(key: key, title: title(for: key, items: items),
                     items: items.sorted { ($0.size ?? 0) > ($1.size ?? 0) })
        }.sorted { lhs, rhs in
            if lhs.totalSize != rhs.totalSize { return lhs.totalSize > rhs.totalSize }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}
