import Foundation

struct DUTreeData: Sendable {
    let sizeMap: [String: Int64]
    let childrenMap: [String: [String]]
    let rootPath: String
}

enum FolderSizeCalculator {
    static func fullSnapshot(path: String, depth: Int) async -> String? {
        await Task.detached(priority: .userInitiated) {
            runDU(path: path, depth: depth)
        }.value
    }

    static func buildTree(from output: String, rootURL: URL) -> FileNode? {
        let data = parseTree(from: output, rootURL: rootURL)
        guard data.sizeMap[data.rootPath] != nil || !(data.childrenMap[data.rootPath] ?? []).isEmpty else {
            return nil
        }
        return assembleTree(from: data, at: data.rootPath).map { sortTreeBySize($0) }
    }

    static func parseTree(from output: String, rootURL: URL) -> DUTreeData {
        let rootPath = rootURL.standardizedFileURL.path
        var sizeMap: [String: Int64] = [:]
        var childrenMap: [String: [String]] = [:]

        for line in output.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init)
            guard parts.count >= 2, let kb = Int64(parts[0]) else { continue }

            let entryPath = URL(fileURLWithPath: parts[1], isDirectory: true).standardizedFileURL.path
            sizeMap[entryPath] = kb * 1024

            let parentPath = URL(fileURLWithPath: entryPath, isDirectory: true)
                .deletingLastPathComponent()
                .standardizedFileURL
                .path

            guard parentPath != entryPath else { continue }
            childrenMap[parentPath, default: []].append(entryPath)
        }

        return DUTreeData(sizeMap: sizeMap, childrenMap: childrenMap, rootPath: rootPath)
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

    private static func runDU(path: String, depth: Int) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-x", "-k", "-d", "\(depth)", path]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return nil
        }

        // du часто повертає exit 1 через TCC, але stdout містить розміри
        return output
    }
}
