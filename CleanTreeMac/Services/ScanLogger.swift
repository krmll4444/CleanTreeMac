import Foundation

enum ScanLogger {
    /// Дублює в UI-лог повідомлення з обраних тегів під час сканування.
    static var uiForwardFilter: (@Sendable (String) -> Bool)?
    static var uiForwardHandler: (@Sendable (String) -> Void)?

    static func scan(_ message: String) {
        write(tag: "scan", message)
    }

    static func du(_ message: String) {
        write(tag: "du", message)
    }

    static func fast(_ message: String) {
        write(tag: "fast", message)
    }

    static func bulk(_ message: String) {
        write(tag: "bulk", message)
    }

    static func tree(_ message: String) {
        write(tag: "tree", message)
    }

    static func merge(_ message: String) {
        write(tag: "merge", message)
    }

    static func size(_ bytes: Int64) -> String {
        ByteFormat.string(for: bytes)
    }

    private static func write(tag: String, _ message: String) {
        let timestamp = ScanLogFormat.timestamp()
        print("[\(tag)] \(timestamp)  \(message)")
        if let uiForwardFilter, uiForwardFilter(tag) {
            uiForwardHandler?("[\(tag)] \(message)")
        }
    }
}
