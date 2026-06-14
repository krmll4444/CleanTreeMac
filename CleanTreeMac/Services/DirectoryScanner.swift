import Foundation

enum DirectoryScanner {
    private static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey,
        .fileSizeKey,
        .totalFileAllocatedSizeKey,
        .isSymbolicLinkKey
    ]

    private static let skippedPaths: Set<String> = [
        "/dev",
        "/.vol",
        "/.nofollow",
        "/.resolve"
    ]

    static let defaultFolderScanDepth = 4
    static let smallRootItemThreshold: Int64 = 2_147_483_648 // 2 GB

    static func scan(
        url: URL,
        maxDepth: Int? = nil,
        onProgress: (@Sendable (ScanProgress) -> Void)? = nil,
        onPartialUpdate: (@Sendable (FileNode) -> Void)? = nil
    ) async -> FileNode {
        if url.path == "/" {
            return await scanMacintoshHD(onProgress: onProgress, onPartialUpdate: onPartialUpdate)
        }
        return await scanFolder(at: url, depth: maxDepth ?? defaultFolderScanDepth, onProgress: onProgress)
    }

    static func scanDepth(for url: URL) -> Int {
        url.path == "/" ? 1 : defaultFolderScanDepth
    }

    static func listVolumes() -> [URL] {
        (FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeNameKey, .volumeIsRemovableKey],
            options: [.skipHiddenVolumes]
        ) ?? []).sorted { $0.path < $1.path }
    }

    static func scanMacintoshHD(
        onProgress: (@Sendable (ScanProgress) -> Void)? = nil,
        onPartialUpdate: (@Sendable (FileNode) -> Void)? = nil
    ) async -> FileNode {
        let rootURL = SystemPaths.systemRoot
        let volume = VolumeStats.forVolume(at: rootURL)

        var latestRoot = await fallbackMacintoshHD(volume: volume, includeHiddenSpace: false)

        // Етап 1: швидкий огляд верхнього рівня
        if let output = await FolderSizeCalculator.fullSnapshot(path: "/", depth: 2),
           let tree = FolderSizeCalculator.buildTree(from: output, rootURL: rootURL) {
            latestRoot = macintoshHDRoot(from: tree, volume: volume, includeHiddenSpace: false)
            onProgress?(ScanProgress(scannedFolders: lineCount(in: output), currentPath: "/"))
            onPartialUpdate?(latestRoot)
        }

        // Етап 2: уточнене дерево для навігації
        if let output = await FolderSizeCalculator.fullSnapshot(path: "/", depth: 5),
           let tree = FolderSizeCalculator.buildTree(from: output, rootURL: rootURL) {
            latestRoot = macintoshHDRoot(from: tree, volume: volume, includeHiddenSpace: true)
            onProgress?(ScanProgress(scannedFolders: lineCount(in: output), currentPath: "/"))
        }

        return latestRoot
    }

    static func scanFolder(
        at url: URL,
        depth: Int = defaultFolderScanDepth,
        onProgress: (@Sendable (ScanProgress) -> Void)? = nil
    ) async -> FileNode {
        onProgress?(ScanProgress(scannedFolders: 0, currentPath: url.path))

        if let output = await FolderSizeCalculator.fullSnapshot(path: url.path, depth: depth),
           let tree = FolderSizeCalculator.buildTree(from: output, rootURL: url) {
            onProgress?(ScanProgress(scannedFolders: lineCount(in: output), currentPath: url.path))
            return tree
        }

        return await fallbackFolder(at: url, onProgress: onProgress)
    }

    static func footerItems(for root: FileNode) -> [FileNode] {
        guard root.url.path == "/" else { return [] }

        let volume = VolumeStats.forVolume(at: root.url)
        guard volume.totalCapacity > 0 else { return [] }

        return [
            FileNode(
                name: "вільний простір",
                url: SystemPaths.specialURL("free-space"),
                size: volume.availableCapacity,
                isDirectory: false,
                kind: .freeSpace
            ),
            FileNode(
                name: "вільний + очищуваний",
                url: SystemPaths.specialURL("free-purgeable"),
                size: volume.importantAvailableCapacity,
                isDirectory: false,
                kind: .freeAndPurgeable
            )
        ]
    }

    private static func macintoshHDRoot(
        from duRoot: FileNode,
        volume: VolumeStats,
        includeHiddenSpace: Bool
    ) -> FileNode {
        var priorityChildren: [FileNode] = []
        var otherNodes: [FileNode] = []

        for child in duRoot.children {
            let path = child.url.standardizedFileURL.path
            if SystemPaths.macintoshHDPriorityPaths.contains(path) {
                priorityChildren.append(child)
            } else if !skippedPaths.contains(path) && !path.hasPrefix("/.") {
                otherNodes.append(child)
            }
        }

        for path in SystemPaths.macintoshHDPriorityPaths {
            guard !priorityChildren.contains(where: { $0.url.path == path }) else { continue }
            guard FileManager.default.fileExists(atPath: path) else { continue }

            let url = URL(fileURLWithPath: path, isDirectory: true)
            priorityChildren.append(
                FileNode(
                    name: SystemPaths.displayName(for: url),
                    url: url,
                    size: 0,
                    isDirectory: true
                )
            )
        }

        return buildMacintoshHDRoot(
            priorityChildren: priorityChildren,
            otherNodes: otherNodes,
            volume: volume,
            includeHiddenSpace: includeHiddenSpace
        )
    }

    private static func buildMacintoshHDRoot(
        priorityChildren: [FileNode],
        otherNodes: [FileNode],
        volume: VolumeStats,
        includeHiddenSpace: Bool
    ) -> FileNode {
        var children = priorityChildren
        let largeOthers = otherNodes.filter { $0.size >= smallRootItemThreshold }
        let smallOthers = otherNodes.filter { $0.size < smallRootItemThreshold }
        children.append(contentsOf: largeOthers)

        if !smallOthers.isEmpty {
            let smallSize = smallOthers.reduce(Int64(0)) { $0 + $1.size }
            children.append(
                FileNode(
                    name: "малі об'єкти…",
                    url: SystemPaths.specialURL("small-objects"),
                    size: smallSize,
                    isDirectory: true,
                    children: smallOthers,
                    kind: .groupedSmall
                )
            )
        }

        if includeHiddenSpace {
            let categorizedSize = children.reduce(Int64(0)) { $0 + $1.size }
            let hiddenSize = max(0, volume.totalCapacity - volume.availableCapacity - categorizedSize)
            if hiddenSize > 0 {
                children.append(
                    FileNode(
                        name: "прихований простір…",
                        url: SystemPaths.specialURL("hidden-space"),
                        size: hiddenSize,
                        isDirectory: false,
                        kind: .hiddenSpace
                    )
                )
            }
        }

        children.sort { $0.size > $1.size }
        let categorizedSize = children.reduce(Int64(0)) { $0 + $1.size }

        return FileNode(
            name: SystemPaths.displayName(for: SystemPaths.systemRoot),
            url: SystemPaths.systemRoot,
            size: volume.totalCapacity > 0 ? volume.totalCapacity : categorizedSize,
            isDirectory: true,
            children: children,
            kind: .folder
        )
    }

    private static func fallbackMacintoshHD(volume: VolumeStats, includeHiddenSpace: Bool) async -> FileNode {
        var priorityChildren: [FileNode] = []

        for path in SystemPaths.macintoshHDPriorityPaths {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            guard FileManager.default.fileExists(atPath: path) else { continue }
            priorityChildren.append(await fallbackFolder(at: url))
        }

        return buildMacintoshHDRoot(
            priorityChildren: priorityChildren,
            otherNodes: [],
            volume: volume,
            includeHiddenSpace: includeHiddenSpace
        )
    }

    private static func fallbackFolder(
        at url: URL,
        onProgress: (@Sendable (ScanProgress) -> Void)? = nil
    ) async -> FileNode {
        onProgress?(ScanProgress(scannedFolders: 1, currentPath: url.path))

        let childURLs = immediateChildren(of: url)
        var children: [FileNode] = []
        var totalSize: Int64 = 0

        for childURL in childURLs {
            var isDirectory = false
            if let values = try? childURL.resourceValues(forKeys: [.isDirectoryKey]) {
                isDirectory = values.isDirectory ?? false
            }

            let childSize = fileSize(at: childURL)
            totalSize += childSize

            children.append(
                FileNode(
                    name: SystemPaths.displayName(for: childURL),
                    url: childURL,
                    size: childSize,
                    isDirectory: isDirectory
                )
            )
        }

        children.sort { $0.size > $1.size }

        return FileNode(
            name: SystemPaths.displayName(for: url),
            url: url,
            size: totalSize,
            isDirectory: true,
            children: children
        )
    }

    private static func immediateChildren(of url: URL) -> [URL] {
        let scanURL = url.resolvingSymlinksInPath()
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: scanURL,
            includingPropertiesForKeys: resourceKeys,
            options: []
        ) else {
            return []
        }

        return contents.filter { child in
            !skippedPaths.contains(child.path) && !isSymlink(child)
        }
    }

    private static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
    }

    private static func fileSize(at url: URL) -> Int64 {
        if let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]) {
            if let allocated = values.totalFileAllocatedSize {
                return Int64(allocated)
            }
            if let size = values.fileSize {
                return Int64(size)
            }
        }
        return 0
    }

    private static func lineCount(in output: String) -> Int {
        output.split(separator: "\n", omittingEmptySubsequences: true).count
    }
}
