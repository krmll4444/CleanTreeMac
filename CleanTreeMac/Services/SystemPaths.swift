import Foundation

struct VolumeStats: Sendable {
    let totalCapacity: Int64
    let availableCapacity: Int64
    let importantAvailableCapacity: Int64

    static func forVolume(at url: URL) -> VolumeStats {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]

        guard let values = try? url.resourceValues(forKeys: keys) else {
            return VolumeStats(totalCapacity: 0, availableCapacity: 0, importantAvailableCapacity: 0)
        }

        return VolumeStats(
            totalCapacity: Int64(values.volumeTotalCapacity ?? 0),
            availableCapacity: Int64(values.volumeAvailableCapacity ?? 0),
            importantAvailableCapacity: Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        )
    }
}

enum SystemPaths {
    static var systemRoot: URL {
        URL(fileURLWithPath: "/")
    }

    static let macintoshHDPriorityPaths: [String] = [
        "/Users",
        "/System",
        "/Applications",
        "/Library",
        "/private"
    ]

    static func displayName(for url: URL) -> String {
        if url.path == "/" {
            if let name = (try? url.resourceValues(forKeys: [.volumeNameKey]))?.volumeName,
               !name.isEmpty {
                return name
            }
            return "Macintosh HD"
        }

        let localized = FileManager.default.displayName(atPath: url.path)
        if !localized.isEmpty {
            return localized
        }

        let name = url.lastPathComponent
        return name.isEmpty ? url.path : name
    }

    static func specialURL(_ identifier: String) -> URL {
        URL(fileURLWithPath: "/.cleantree/\(identifier)")
    }
}
