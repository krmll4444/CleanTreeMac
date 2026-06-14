import Foundation

enum ByteFormat {
    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        return f
    }()

    static func string(for bytes: Int64) -> String {
        formatter.string(fromByteCount: bytes)
    }
}

enum ChartPalette {
    static let segmentColors: [Double] = [
        0.72, 0.68, 0.64, 0.60, 0.56, 0.52, 0.48, 0.44, 0.40, 0.36
    ]

    static func hue(for index: Int) -> Double {
        segmentColors[index % segmentColors.count]
    }
}
