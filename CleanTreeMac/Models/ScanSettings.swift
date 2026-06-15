import Foundation

struct ScanSettings: Codable, Equatable, Sendable {
    var paths: [String]

    static let `default` = ScanSettings(paths: SystemPaths.defaultScanPaths)

    private static let userDefaultsKey = "scanSettings"

    static func load() -> ScanSettings {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let settings = try? JSONDecoder().decode(ScanSettings.self, from: data) else {
            return .default
        }
        return settings.sanitized()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(sanitized()) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }

    var orderedPaths: [String] {
        Self.selectablePaths.filter { paths.contains($0) }
    }

    static var selectablePaths: [String] {
        SystemPaths.defaultScanPaths + SystemPaths.optionalScanPaths
    }

    func isEnabled(_ path: String) -> Bool {
        paths.contains(path)
    }

    private func sanitized() -> ScanSettings {
        ScanSettings(paths: Self.selectablePaths.filter { paths.contains($0) })
    }
}
