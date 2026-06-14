import Foundation

struct DiskIndex: Sendable {
    private(set) var root: FileNode?
    private var pathMap: [String: FileNode] = [:]

    var folderCount: Int {
        pathMap.count
    }

    mutating func install(root: FileNode) {
        self.root = root
        pathMap.removeAll(keepingCapacity: true)
        index(node: root)
    }

    mutating func merge(_ node: FileNode) {
        guard var root else {
            install(root: node)
            return
        }

        let targetPath = node.url.standardizedFileURL.path

        if let oldNode = pathMap[targetPath] {
            deindex(node: oldNode)
        }

        root = replaceNode(matching: node.url, in: root, with: node) ?? root
        self.root = root

        index(node: node)
        refreshAncestors(of: targetPath, in: root)
    }

    func node(at url: URL) -> FileNode? {
        pathMap[url.standardizedFileURL.path]
    }

    private mutating func index(node: FileNode) {
        pathMap[node.url.standardizedFileURL.path] = node
        for child in node.children {
            index(node: child)
        }
    }

    private mutating func deindex(node: FileNode) {
        pathMap.removeValue(forKey: node.url.standardizedFileURL.path)
        for child in node.children {
            deindex(node: child)
        }
    }

    private mutating func refreshAncestors(of targetPath: String, in root: FileNode) {
        guard let chain = pathNodes(from: root, to: targetPath) else { return }
        for ancestor in chain {
            pathMap[ancestor.url.standardizedFileURL.path] = ancestor
        }
    }

    private func pathNodes(from node: FileNode, to targetPath: String) -> [FileNode]? {
        if node.url.standardizedFileURL.path == targetPath {
            return [node]
        }

        for child in node.children {
            if let chain = pathNodes(from: child, to: targetPath) {
                return [node] + chain
            }
        }
        return nil
    }

    private func replaceNode(matching url: URL, in node: FileNode, with replacement: FileNode) -> FileNode? {
        if node.url.standardizedFileURL == url.standardizedFileURL {
            return replacement
        }

        let updatedChildren = node.children.map { child in
            replaceNode(matching: url, in: child, with: replacement) ?? child
        }

        let totalSize = updatedChildren.reduce(Int64(0)) { $0 + $1.size }
        return FileNode(
            id: node.id,
            name: node.name,
            url: node.url,
            size: totalSize,
            isDirectory: node.isDirectory,
            children: updatedChildren,
            kind: node.kind
        )
    }
}

struct ScanProgress: Sendable {
    let scannedFolders: Int
    let currentPath: String
}
