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
        ScanLogger.scan("scan url=\(url.path) maxDepth=\(maxDepth?.description ?? "nil")")
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
        let settings = ScanSettings.load()
        let paths = settings.orderedPaths.filter { path in
            !SystemPaths.excludedFromScan.contains(path)
                && FileManager.default.fileExists(atPath: path)
        }
        let volume = VolumeStats.forVolume(at: SystemPaths.systemRoot)
        let scanDepth = 4
        let counter = ScanFolderCounter()
        let accumulator = MacintoshHDScanAccumulator(paths: paths, volume: volume)

        ScanLogger.scan(
            "scanMacintoshHD start depth=\(scanDepth) paths=[\(paths.joined(separator: ", "))] " +
            "volume=\(ScanLogger.size(volume.totalCapacity)) " +
            "free=\(ScanLogger.size(volume.availableCapacity))"
        )

        if paths.isEmpty {
            ScanLogger.scan("scanMacintoshHD no paths selected — returning placeholder root")
            let root = await accumulator.currentRoot(includeHiddenSpace: true)
            onPartialUpdate?(root)
            return root
        }

        let scanStart = Date()
        await withTaskGroup(of: ScanPathResult.self) { group in
            for path in paths {
                group.addTask {
                    let start = Date()
                    ScanLogger.scan("task start path=\(path) depth=\(scanDepth)")

                    let result: ScanPathResult
                    if Task.isCancelled {
                        ScanLogger.scan("task cancelled before start path=\(path)")
                        result = ScanPathResult(path: path, tree: nil, folderCount: 0, method: .cancelled)
                    } else {
                        let url = URL(fileURLWithPath: path, isDirectory: true)
                        onProgress?(ScanProgress(scannedFolders: 0, currentPath: path))
                        if let output = await FolderSizeCalculator.fullSnapshot(path: path, depth: scanDepth),
                           let tree = FolderSizeCalculator.buildTree(from: output, rootURL: url) {
                            ScanLogger.scan("task du ok path=\(path) folders=\(lineCount(in: output))")
                            result = ScanPathResult(
                                path: path,
                                tree: tree,
                                folderCount: lineCount(in: output),
                                method: .du
                            )
                        } else {
                            ScanLogger.scan("task du failed — trying FastDirectoryScanner path=\(path)")
                            let pathCounter = ScanFolderCounter()
                            if let tree = await FastDirectoryScanner.scan(url: url, maxDepth: scanDepth, onProgress: { scanPath in
                                let n = pathCounter.increment()
                                onProgress?(ScanProgress(scannedFolders: n, currentPath: scanPath))
                            }) {
                                ScanLogger.scan("task fast ok path=\(path) folders=\(pathCounter.value)")
                                result = ScanPathResult(
                                    path: path,
                                    tree: tree,
                                    folderCount: pathCounter.value,
                                    method: .fast
                                )
                            } else {
                                ScanLogger.scan("task failed path=\(path) — no tree from du or fast scanner")
                                result = ScanPathResult(path: path, tree: nil, folderCount: 0, method: .failed)
                            }
                        }
                    }

                    let elapsed = Date().timeIntervalSince(start)
                    ScanLogger.scan(
                        "task done path=\(path) method=\(result.method.rawValue) " +
                        "took=\(String(format: "%.2f", elapsed))s folders=\(result.folderCount) " +
                        "treeSize=\(result.tree.map { ScanLogger.size($0.size) } ?? "nil") " +
                        "children=\(result.tree?.children.count ?? 0)"
                    )
                    return result
                }
            }

            for await result in group {
                if Task.isCancelled {
                    ScanLogger.scan("scanMacintoshHD cancelled — stopping merge loop")
                    group.cancelAll()
                    break
                }

                counter.add(result.folderCount)
                onProgress?(
                    ScanProgress(
                        scannedFolders: counter.value,
                        currentPath: result.path
                    )
                )

                let partial = await accumulator.mergeResult(result.tree, path: result.path)
                ScanLogger.merge(
                    "partial update path=\(result.path) method=\(result.method.rawValue) " +
                    "rootChildren=\(partial.children.count) " +
                    "rootSize=\(ScanLogger.size(partial.size))"
                )
                onPartialUpdate?(partial)
            }
        }

        let finalRoot = await accumulator.currentRoot(includeHiddenSpace: true)
        let totalElapsed = Date().timeIntervalSince(scanStart)
        ScanLogger.scan(
            "scanMacintoshHD done took=\(String(format: "%.2f", totalElapsed))s " +
            "totalFolders=\(counter.value) rootChildren=\(finalRoot.children.count) " +
            "rootSize=\(ScanLogger.size(finalRoot.size))"
        )
        return finalRoot
    }

    static func scanFolder(
        at url: URL,
        depth: Int = defaultFolderScanDepth,
        onProgress: (@Sendable (ScanProgress) -> Void)? = nil
    ) async -> FileNode {
        ScanLogger.scan("scanFolder start path=\(url.path) depth=\(depth)")
        onProgress?(ScanProgress(scannedFolders: 0, currentPath: url.path))

        if let tree = await scanWithFastScanner(url: url, depth: depth, onProgress: onProgress) {
            ScanLogger.scan(
                "scanFolder done path=\(url.path) method=du " +
                "size=\(ScanLogger.size(tree.size)) children=\(tree.children.count)"
            )
            return tree
        }

        ScanLogger.scan("scanFolder fallback path=\(url.path)")
        let tree = await fallbackFolder(at: url, onProgress: onProgress)
        ScanLogger.scan(
            "scanFolder fallback done path=\(url.path) " +
            "size=\(ScanLogger.size(tree.size)) children=\(tree.children.count)"
        )
        return tree
    }

    private static func scanWithFastScanner(
        url: URL,
        depth: Int,
        onProgress: (@Sendable (ScanProgress) -> Void)?
    ) async -> FileNode? {
        ScanLogger.scan("scanWithFastScanner try du path=\(url.path) depth=\(depth)")
        if let output = await FolderSizeCalculator.fullSnapshot(path: url.path, depth: depth),
           let tree = FolderSizeCalculator.buildTree(from: output, rootURL: url) {
            onProgress?(ScanProgress(scannedFolders: lineCount(in: output), currentPath: url.path))
            return tree
        }
        ScanLogger.scan("scanWithFastScanner du failed path=\(url.path)")
        return nil
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

    static func buildMacintoshHDRoot(
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

private struct ScanPathResult: Sendable {
    enum Method: String, Sendable {
        case du
        case fast
        case failed
        case cancelled
    }

    let path: String
    let tree: FileNode?
    let folderCount: Int
    let method: Method
}

private actor MacintoshHDScanAccumulator {
    private var diskIndex = DiskIndex()
    private let volume: VolumeStats
    private let totalPaths: Int
    private var completedPaths = 0

    init(paths: [String], volume: VolumeStats) {
        self.volume = volume
        self.totalPaths = paths.count

        let rootURL = SystemPaths.systemRoot
        let placeholders = paths.map { path -> FileNode in
            let url = URL(fileURLWithPath: path, isDirectory: true)
            return FileNode(
                name: SystemPaths.displayName(for: url),
                url: url,
                size: 0,
                isDirectory: true
            )
        }

        let root = FileNode(
            name: SystemPaths.displayName(for: rootURL),
            url: rootURL,
            size: volume.totalCapacity,
            isDirectory: true,
            children: placeholders
        )
        diskIndex.install(root: root)
        ScanLogger.merge(
            "accumulator init placeholders=[\(paths.joined(separator: ", "))] " +
            "volume=\(ScanLogger.size(volume.totalCapacity))"
        )
    }

    func mergeResult(_ tree: FileNode?, path: String) -> FileNode {
        completedPaths += 1
        if let tree {
            ScanLogger.merge(
                "merge path=\(path) size=\(ScanLogger.size(tree.size)) " +
                "children=\(tree.children.count) progress=\(completedPaths)/\(totalPaths)"
            )
            diskIndex.merge(tree)
        } else {
            ScanLogger.merge("merge skipped — nil tree for path=\(path) progress=\(completedPaths)/\(totalPaths)")
        }
        return buildRoot(includeHiddenSpace: completedPaths >= totalPaths)
    }

    func currentRoot(includeHiddenSpace: Bool) -> FileNode {
        buildRoot(includeHiddenSpace: includeHiddenSpace)
    }

    private func buildRoot(includeHiddenSpace: Bool) -> FileNode {
        let children = diskIndex.root?.children ?? []
        return DirectoryScanner.buildMacintoshHDRoot(
            priorityChildren: children.sorted { $0.size > $1.size },
            otherNodes: [],
            volume: volume,
            includeHiddenSpace: includeHiddenSpace
        )
    }
}

private final class ScanFolderCounter: @unchecked Sendable {
    private var count = 0
    private let lock = NSLock()

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() -> Int {
        lock.lock()
        count += 1
        let current = count
        lock.unlock()
        return current
    }

    func add(_ amount: Int) {
        guard amount > 0 else { return }
        lock.lock()
        count += amount
        lock.unlock()
    }
}
