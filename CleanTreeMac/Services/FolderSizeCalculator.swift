import Foundation

struct DUTreeData: Sendable {
    let sizeMap: [String: Int64]
    let childrenMap: [String: [String]]
    let rootPath: String
    let skippedLines: Int
    let malformedLines: Int
}

enum FolderSizeCalculator {
    static func cancelActiveProcesses() {
        DUProcessRegistry.shared.terminateAll()
    }

    static func fullSnapshot(path: String, depth: Int) async -> String? {
        ScanLogger.du("start path=\(path) depth=\(depth) cmd=/usr/bin/du -x -k -d \(depth) \(path)")
        logPreflight(for: path)

        let output = await withTaskCancellationHandler {
            await runDU(path: path, depth: depth)
        } onCancel: {
            ScanLogger.du("cancel requested path=\(path)")
            DUProcessRegistry.shared.terminateAll()
        }
        if output == nil {
            ScanLogger.du("no output path=\(path) depth=\(depth)")
        }
        return output
    }

    static func buildTree(from output: String, rootURL: URL) -> FileNode? {
        let data = parseTree(from: output, rootURL: rootURL)
        let rootSize = data.sizeMap[data.rootPath] ?? 0
        let childCount = data.childrenMap[data.rootPath]?.count ?? 0
        ScanLogger.tree(
            "parse root=\(data.rootPath) paths=\(data.sizeMap.count) " +
            "rootChildren=\(childCount) rootSize=\(ScanLogger.size(rootSize)) " +
            "skippedLines=\(data.skippedLines) malformedLines=\(data.malformedLines)"
        )
        guard data.sizeMap[data.rootPath] != nil || !(data.childrenMap[data.rootPath] ?? []).isEmpty else {
            ScanLogger.tree("buildTree failed — empty data for \(data.rootPath)")
            return nil
        }
        guard let tree = assembleTree(from: data, at: data.rootPath).map({ sortTreeBySize($0) }) else {
            ScanLogger.tree("buildTree failed — assembleTree returned nil for \(data.rootPath)")
            return nil
        }
        ScanLogger.tree(
            "built root=\(tree.url.path) size=\(ScanLogger.size(tree.size)) " +
            "children=\(tree.children.count)"
        )
        return tree
    }

    static func parseTree(from output: String, rootURL: URL) -> DUTreeData {
        let rootPath = rootURL.standardizedFileURL.path
        var sizeMap: [String: Int64] = [:]
        var childrenMap: [String: [String]] = [:]
        var skippedLines = 0
        var malformedLines = 0

        for line in output.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init)
            guard parts.count >= 2, let kb = Int64(parts[0]) else {
                malformedLines += 1
                if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    ScanLogger.tree("malformed line: \(line.prefix(120))")
                }
                continue
            }

            let entryPath = URL(fileURLWithPath: parts[1], isDirectory: true).standardizedFileURL.path
            sizeMap[entryPath] = kb * 1024

            let parentPath = URL(fileURLWithPath: entryPath, isDirectory: true)
                .deletingLastPathComponent()
                .standardizedFileURL
                .path

            guard parentPath != entryPath else {
                skippedLines += 1
                continue
            }
            childrenMap[parentPath, default: []].append(entryPath)
        }

        return DUTreeData(
            sizeMap: sizeMap,
            childrenMap: childrenMap,
            rootPath: rootPath,
            skippedLines: skippedLines,
            malformedLines: malformedLines
        )
    }

    private static func assembleTree(from data: DUTreeData, at path: String) -> FileNode? {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        let size = data.sizeMap[path] ?? 0
        let childPaths = data.childrenMap[path] ?? []

        let children = childPaths.compactMap { assembleTree(from: data, at: $0) }
        let isDirectory = !children.isEmpty || path == data.rootPath

        return FileNode(
            name: SystemPaths.displayName(for: url),
            url: url,
            size: size,
            isDirectory: isDirectory,
            children: children
        )
    }

    private static func sortTreeBySize(_ node: FileNode) -> FileNode {
        let sortedChildren = node.children
            .map { sortTreeBySize($0) }
            .sorted { $0.size > $1.size }

        return FileNode(
            id: node.id,
            name: node.name,
            url: node.url,
            size: node.size,
            isDirectory: node.isDirectory,
            children: sortedChildren,
            kind: node.kind
        )
    }

    private static func logPreflight(for path: String) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: path, isDirectory: &isDir)
        let readable = fm.isReadableFile(atPath: path)
        let duExists = fm.isExecutableFile(atPath: "/usr/bin/du")
        ScanLogger.du(
            "preflight path=\(path) exists=\(exists) isDir=\(isDir.boolValue) " +
            "readable=\(readable) duExecutable=\(duExists)"
        )
        if !exists {
            ScanLogger.du("preflight warning — path does not exist: \(path)")
        } else if !readable {
            ScanLogger.du("preflight warning — path not readable (TCC?): \(path)")
        }
        if !duExists {
            ScanLogger.du("preflight error — /usr/bin/du not executable")
        }
    }

    private static func runDU(path: String, depth: Int) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-x", "-k", "-d", "\(depth)", path]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let collector = DUStreamCollector(path: path)

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            collector.appendStdout(data)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            collector.appendStderr(data)
        }

        DUProcessRegistry.shared.register(process)
        defer {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            DUProcessRegistry.shared.unregister(process)
        }

        var waitedMs = 0
        var lastStdoutBytes = 0
        var lastProgressAtMs = 0

        do {
            try process.run()
            ScanLogger.du("running pid=\(process.processIdentifier) path=\(path)")
        } catch {
            ScanLogger.du("launch failed path=\(path) error=\(error.localizedDescription)")
            return nil
        }

        while process.isRunning {
            if Task.isCancelled {
                ScanLogger.du("terminated path=\(path) reason=task-cancelled")
                process.terminate()
                return nil
            }

            waitedMs += 100

            if waitedMs % 5000 == 0 {
                let snap = collector.snapshot()
                let stderrPreview = collector.recentStderrSummary(maxLines: 3)
                let stdoutDelta = snap.stdoutBytes - lastStdoutBytes
                lastStdoutBytes = snap.stdoutBytes

                ScanLogger.du(
                    "still running path=\(path) pid=\(process.processIdentifier) " +
                    "waited=\(waitedMs / 1000)s stdout=\(ScanLogger.size(Int64(snap.stdoutBytes))) " +
                    "lines≈\(snap.stdoutLines) stderrLines=\(snap.stderrLines) " +
                    "stdoutDelta5s=\(ScanLogger.size(Int64(stdoutDelta)))"
                )

                if !stderrPreview.isEmpty {
                    ScanLogger.du("recent stderr: \(stderrPreview)")
                }

                if stdoutDelta == 0, waitedMs - lastProgressAtMs >= 30_000 {
                    ScanLogger.du(
                        "warning path=\(path) — stdout не росте 30s+ " +
                        "(du може чекати на I/O або блокуватись на доступі до файлу)"
                    )
                } else if stdoutDelta > 0 {
                    lastProgressAtMs = waitedMs
                }
            }

            try? await Task.sleep(for: .milliseconds(100))
        }

        if Task.isCancelled {
            ScanLogger.du("aborted path=\(path) reason=task-cancelled-after-exit")
            return nil
        }

        // Дочитати залишки після закриття handlers
        collector.appendStdout(outputPipe.fileHandleForReading.readDataToEndOfFile())
        collector.appendStderr(errorPipe.fileHandleForReading.readDataToEndOfFile())

        let snap = collector.snapshot()
        let exitCode = process.terminationStatus
        let reason = process.terminationReason
        let reasonLabel = terminationLabel(reason: reason, status: exitCode)

        ScanLogger.du(
            "done path=\(path) depth=\(depth) \(reasonLabel) " +
            "stdout=\(ScanLogger.size(Int64(snap.stdoutBytes))) lines≈\(snap.stdoutLines) " +
            "stderrLines=\(snap.stderrLines)"
        )

        if !snap.stderrText.isEmpty {
            for line in snap.stderrText.split(separator: "\n") {
                let text = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                ScanLogger.du("stderr path=\(path) \(text)")
            }
        }

        if snap.stdoutBytes == 0, snap.stderrLines > 0 {
            ScanLogger.du(
                "empty stdout with stderr — likely permission/TCC issue for path=\(path)"
            )
        }

        guard let output = String(data: snap.stdoutData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            ScanLogger.du("empty stdout path=\(path) \(reasonLabel)")
            return nil
        }

        // du часто повертає exit 1 через TCC, але stdout містить розміри
        if exitCode != 0 {
            ScanLogger.du(
                "non-zero exit path=\(path) \(reasonLabel) — using stdout anyway " +
                "(du exit 1 часто через Permission denied на окремих файлах)"
            )
        }

        return output
    }

    private static func terminationLabel(reason: Process.TerminationReason, status: Int32) -> String {
        switch reason {
        case .exit:
            return "exit=\(status)"
        case .uncaughtSignal:
            return "signal=\(status) (\(signalName(status)))"
        @unknown default:
            return "reason=\(reason.rawValue) status=\(status)"
        }
    }

    private static func signalName(_ signal: Int32) -> String {
        switch signal {
        case SIGTERM: return "SIGTERM"
        case SIGKILL: return "SIGKILL"
        case SIGINT: return "SIGINT"
        default: return "signal \(signal)"
        }
    }
}

// MARK: - Stream collector (запобігає блокуванню pipe)

private final class DUStreamCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()
    private var stdoutLineCount = 0
    private var stderrLineCount = 0
    private var stderrLines: [String] = []
    private var lastStdoutLogMilestone = 0
    let path: String

    init(path: String) {
        self.path = path
    }

    func appendStdout(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        stdoutData.append(data)
        stdoutLineCount += data.reduce(into: 0) { count, byte in
            if byte == 0x0A { count += 1 }
        }
        let bytes = stdoutData.count
        let lines = stdoutLineCount
        let milestone = lines / 500
        let shouldLog = milestone > lastStdoutLogMilestone
        if shouldLog {
            lastStdoutLogMilestone = milestone
        }
        lock.unlock()

        if shouldLog, lines > 0 {
            ScanLogger.du(
                "stdout progress path=\(path) lines≈\(lines) " +
                "bytes=\(ScanLogger.size(Int64(bytes)))"
            )
        }
    }

    func appendStderr(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        stderrData.append(data)
        lock.unlock()

        guard let chunk = String(data: data, encoding: .utf8) else {
            ScanLogger.du("stderr path=\(path) (non-utf8 chunk \(data.count) bytes)")
            return
        }

        for line in chunk.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            lock.lock()
            stderrLineCount += 1
            stderrLines.append(text)
            if stderrLines.count > 50 {
                stderrLines.removeFirst(stderrLines.count - 50)
            }
            lock.unlock()
            ScanLogger.du("stderr path=\(path) \(text)")
        }
    }

    func snapshot() -> (stdoutData: Data, stdoutBytes: Int, stdoutLines: Int, stderrLines: Int, stderrText: String) {
        lock.lock()
        defer { lock.unlock() }
        let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
        return (stdoutData, stdoutData.count, stdoutLineCount, stderrLineCount, stderrText)
    }

    func recentStderrSummary(maxLines: Int) -> String {
        lock.lock()
        defer { lock.unlock() }
        return stderrLines.suffix(maxLines).joined(separator: " | ")
    }
}

private final class DUProcessRegistry: @unchecked Sendable {
    static let shared = DUProcessRegistry()

    private var processes: [Process] = []
    private let lock = NSLock()

    func register(_ process: Process) {
        lock.lock()
        processes.append(process)
        lock.unlock()
    }

    func unregister(_ process: Process) {
        lock.lock()
        processes.removeAll { $0 === process }
        lock.unlock()
    }

    func terminateAll() {
        lock.lock()
        let running = processes
        processes.removeAll()
        lock.unlock()

        ScanLogger.du("terminateAll count=\(running.count)")
        for process in running where process.isRunning {
            ScanLogger.du("terminating pid=\(process.processIdentifier)")
            process.terminate()
        }
    }
}
