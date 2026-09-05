import Foundation

public enum FileSizer {
    public static func allocatedSize(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isSymbolicLink == true { return 0 }
        if values.isDirectory != true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }
        ) else { return 0 }
        var total: Int64 = 0
        while let child = enumerator.nextObject() as? URL {
            guard let v = try? child.resourceValues(forKeys: keys), v.isDirectory != true, v.isSymbolicLink != true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }

    static func measure(_ items: [LeftoverItem], concurrency: Int = 6,
                        progress: (@Sendable (Int) -> Void)? = nil) async -> [LeftoverItem] {
        var result = items
        await withTaskGroup(of: (Int, Int64).self) { group in
            var next = 0
            var done = 0
            func enqueue() {
                guard next < items.count else { return }
                let index = next
                let url = items[index].url
                next += 1
                group.addTask { (index, allocatedSize(of: url)) }
            }
            for _ in 0..<concurrency { enqueue() }
            for await (index, size) in group {
                result[index].size = size
                done += 1
                progress?(done)
                enqueue()
            }
        }
        return result
    }
}
