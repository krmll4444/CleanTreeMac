import Darwin
import Foundation

enum FastDirectoryScanner {
    static func scan(
        url: URL,
        maxDepth: Int,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async -> FileNode? {
        await Task.detached(priority: .userInitiated) {
            let rootURL = url.standardizedFileURL
            ScanLogger.fast("scan start path=\(rootURL.path) maxDepth=\(maxDepth)")
            let start = Date()
            let scanner = BulkScanner(
                rootURL: rootURL,
                maxDepth: max(maxDepth, 0),
                onProgress: onProgress
            )
            guard let root = scanner.scanDirectory(at: rootURL, currentDepth: 0) else {
                ScanLogger.fast("scan failed — cannot open root path=\(rootURL.path)")
                return nil
            }
            let sorted = sortTreeBySize(root)
            let elapsed = Date().timeIntervalSince(start)
            ScanLogger.fast(
                "scan done path=\(rootURL.path) took=\(String(format: "%.2f", elapsed))s " +
                "size=\(ScanLogger.size(sorted.size)) children=\(sorted.children.count)"
            )
            return sorted
        }.value
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
}

// MARK: - Scanner

private final class BulkScanner: @unchecked Sendable {
    private static let skippedPaths: Set<String> = [
        "/dev",
        "/.vol",
        "/.nofollow",
        "/.resolve"
    ]

    private static let bufferSize = 256 * 1024

    private let rootURL: URL
    private let maxDepth: Int
    private let onProgress: (@Sendable (String) -> Void)?

    init(
        rootURL: URL,
        maxDepth: Int,
        onProgress: (@Sendable (String) -> Void)?
    ) {
        self.rootURL = rootURL
        self.maxDepth = maxDepth
        self.onProgress = onProgress
    }

    func scanDirectory(at url: URL, currentDepth: Int) -> FileNode? {
        let path = url.standardizedFileURL.path
        onProgress?(path)

        let dirfd = open(path, O_RDONLY | O_DIRECTORY)
        guard dirfd >= 0 else {
            ScanLogger.fast("open failed path=\(path) depth=\(currentDepth)/\(maxDepth) errno=\(errno)")
            if currentDepth == 0 { return nil }
            return makeDirectoryNode(url: url, size: 0, children: [])
        }
        defer { close(dirfd) }

        var directFileBytes: Int64 = 0
        var childNodes: [FileNode] = []
        var childDirectoriesToScan: [(name: String, url: URL)] = []
        var fileCount = 0
        var dirCount = 0
        var skippedCount = 0

        for entry in listEntries(dirfd: dirfd, baseURL: url) {
            if entry.isDirectory {
                guard !Self.skippedPaths.contains(entry.url.path) else {
                    skippedCount += 1
                    continue
                }
                dirCount += 1

                if currentDepth < maxDepth {
                    childDirectoriesToScan.append((entry.name, entry.url))
                } else {
                    let subtreeStart = Date()
                    let subtreeSize = measureSubtreeSize(at: entry.url)
                    directFileBytes += subtreeSize
                    ScanLogger.fast(
                        "measureSubtree path=\(entry.url.path) depth=\(currentDepth)/\(maxDepth) " +
                        "size=\(ScanLogger.size(subtreeSize)) " +
                        "took=\(String(format: "%.3f", Date().timeIntervalSince(subtreeStart)))s"
                    )
                }
            } else if entry.isRegularFile {
                fileCount += 1
                directFileBytes += entry.allocatedSize
            }
        }

        if childDirectoriesToScan.count == 1 {
            if let child = scanDirectory(at: childDirectoriesToScan[0].url, currentDepth: currentDepth + 1) {
                childNodes.append(child)
            }
        } else if !childDirectoriesToScan.isEmpty {
            ScanLogger.fast(
                "parallel recurse path=\(path) depth=\(currentDepth)/\(maxDepth) " +
                "children=\(childDirectoriesToScan.count)"
            )
            childNodes.append(contentsOf: scanChildrenInParallel(childDirectoriesToScan, currentDepth: currentDepth))
        }

        let childrenBytes = childNodes.reduce(Int64(0)) { $0 + $1.size }
        let totalSize = directFileBytes + childrenBytes

        ScanLogger.fast(
            "dir done path=\(path) depth=\(currentDepth)/\(maxDepth) " +
            "files=\(fileCount) dirs=\(dirCount) skipped=\(skippedCount) " +
            "recurse=\(childDirectoriesToScan.count) " +
            "fileBytes=\(ScanLogger.size(directFileBytes)) " +
            "childBytes=\(ScanLogger.size(childrenBytes)) " +
            "total=\(ScanLogger.size(totalSize))"
        )

        return makeDirectoryNode(url: url, size: totalSize, children: childNodes)
    }

    private func scanChildrenInParallel(
        _ children: [(name: String, url: URL)],
        currentDepth: Int
    ) -> [FileNode] {
        var nodes = [FileNode?](repeating: nil, count: children.count)

        DispatchQueue.concurrentPerform(iterations: children.count) { index in
            nodes[index] = scanDirectory(at: children[index].url, currentDepth: currentDepth + 1)
        }

        return nodes.compactMap { $0 }
    }

    private func measureSubtreeSize(at url: URL) -> Int64 {
        let path = url.standardizedFileURL.path

        let dirfd = open(path, O_RDONLY | O_DIRECTORY)
        guard dirfd >= 0 else { return 0 }
        defer { close(dirfd) }

        var total: Int64 = 0
        var childDirectoryURLs: [URL] = []

        for entry in listEntries(dirfd: dirfd, baseURL: url) {
            if entry.isRegularFile {
                total += entry.allocatedSize
            } else if entry.isDirectory {
                guard !Self.skippedPaths.contains(entry.url.path) else { continue }
                childDirectoryURLs.append(entry.url)
            }
        }

        guard !childDirectoryURLs.isEmpty else { return total }

        if childDirectoryURLs.count == 1 {
            return total + measureSubtreeSize(at: childDirectoryURLs[0])
        }

        var childSizes = [Int64](repeating: 0, count: childDirectoryURLs.count)
        DispatchQueue.concurrentPerform(iterations: childDirectoryURLs.count) { index in
            childSizes[index] = measureSubtreeSize(at: childDirectoryURLs[index])
        }

        return total + childSizes.reduce(0, +)
    }

    private func makeDirectoryNode(url: URL, size: Int64, children: [FileNode]) -> FileNode {
        FileNode(
            name: SystemPaths.displayName(for: url),
            url: url.standardizedFileURL,
            size: size,
            isDirectory: true,
            children: children
        )
    }

    private func listEntries(dirfd: Int32, baseURL: URL) -> [BulkDirectoryEntry] {
        var entries: [BulkDirectoryEntry] = []
        var buffer = [UInt8](repeating: 0, count: Self.bufferSize)

        let requestList = BulkAttributeParser.requestListPointer()
        var batchIndex = 0
        var bulkErrors = 0

        while true {
            batchIndex += 1
            let count: Int32 = buffer.withUnsafeMutableBytes { rawBuffer in
                guard let base = rawBuffer.baseAddress else { return -1 }
                return getattrlistbulk(
                    dirfd,
                    requestList,
                    base,
                    rawBuffer.count,
                    UInt64(FSOPT_PACK_INVAL_ATTRS)
                )
            }

            if count == 0 { break }
            if count < 0 {
                bulkErrors += 1
                ScanLogger.bulk(
                    "getattrlistbulk error dir=\(baseURL.path) batch=\(batchIndex) " +
                    "errno=\(errno) (\(String(cString: strerror(errno)))"
                )
                break
            }

            let before = entries.count
            buffer.withUnsafeBytes { rawBuffer in
                guard let base = rawBuffer.baseAddress else { return }
                BulkAttributeParser.parseEntries(
                    in: base,
                    count: Int(count),
                    baseURL: baseURL,
                    into: &entries
                )
            }
            ScanLogger.bulk(
                "batch dir=\(baseURL.path) batch=\(batchIndex) " +
                "returned=\(count) parsed=\(entries.count - before) total=\(entries.count)"
            )
        }

        if entries.isEmpty {
            ScanLogger.bulk(
                "empty listing dir=\(baseURL.path) batches=\(batchIndex) errors=\(bulkErrors)"
            )
        }

        return entries
    }
}

// MARK: - Parsed entry

private struct BulkDirectoryEntry {
    let name: String
    let url: URL
    let objectType: fsobj_type_t
    let allocatedSize: Int64

    var isDirectory: Bool { objectType == numericObjectType(VDIR) }
    var isRegularFile: Bool { objectType == numericObjectType(VREG) }
    var isSymlink: Bool { objectType == numericObjectType(VLNK) }
}

private func numericObjectType(_ type: vtype) -> fsobj_type_t {
    fsobj_type_t(type.rawValue)
}

// MARK: - getattrlistbulk parsing

private enum BulkAttributeParser {
    private static var requestListStorage: attrlist = {
        var list = attrlist()
        list.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        list.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
            | attrgroup_t(ATTR_CMN_NAME)
            | attrgroup_t(ATTR_CMN_OBJTYPE)
            | attrgroup_t(ATTR_CMN_ERROR)
        list.fileattr = attrgroup_t(ATTR_FILE_ALLOCSIZE)
        return list
    }()

    static func requestListPointer() -> UnsafeMutablePointer<attrlist> {
        withUnsafeMutablePointer(to: &requestListStorage) { $0 }
    }

    static func parseEntries(
        in buffer: UnsafeRawPointer,
        count: Int,
        baseURL: URL,
        into entries: inout [BulkDirectoryEntry]
    ) {
        var entryStart = buffer

        for _ in 0..<count {
            guard let parsed = parseEntry(at: entryStart, baseURL: baseURL) else { break }
            entryStart = entryStart.advanced(by: Int(parsed.entryLength))
            if parsed.skip { continue }
            entries.append(parsed.entry)
        }
    }

    private struct ParsedEntry {
        let entry: BulkDirectoryEntry
        let entryLength: UInt32
        let skip: Bool
    }

    private static func parseEntry(at entryStart: UnsafeRawPointer, baseURL: URL) -> ParsedEntry? {
        let length = entryStart.load(as: UInt32.self)
        guard length >= UInt32(MemoryLayout<UInt32>.size + MemoryLayout<attribute_set_t>.size) else {
            return nil
        }

        var field = entryStart.advanced(by: MemoryLayout<UInt32>.size)
        let returned = field.load(as: attribute_set_t.self)
        field = field.advanced(by: MemoryLayout<attribute_set_t>.size)

        var errorCode: UInt32 = 0
        var name = ""
        var objectType: fsobj_type_t = 0
        var allocatedSize: Int64 = 0

        if returned.commonattr & attrgroup_t(ATTR_CMN_NAME) != 0 {
            let nameField = field
            let nameInfo = field.load(as: attrreference_t.self)
            field = field.advanced(by: MemoryLayout<attrreference_t>.size)

            if nameInfo.attr_length > 0 {
                let namePointer = nameField.advanced(by: Int(nameInfo.attr_dataoffset))
                name = String(cString: namePointer.assumingMemoryBound(to: CChar.self))
            }
        }

        if returned.commonattr & attrgroup_t(ATTR_CMN_OBJTYPE) != 0 {
            objectType = field.load(as: fsobj_type_t.self)
            field = field.advanced(by: MemoryLayout<fsobj_type_t>.size)
        }

        if returned.commonattr & attrgroup_t(ATTR_CMN_ERROR) != 0 {
            errorCode = field.load(as: UInt32.self)
            field = field.advanced(by: MemoryLayout<UInt32>.size)
        }

        if returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE) != 0 {
            allocatedSize = Int64(field.load(as: off_t.self))
            field = field.advanced(by: MemoryLayout<off_t>.size)
        }

        if errorCode != 0 {
            return ParsedEntry(
                entry: BulkDirectoryEntry(
                    name: name,
                    url: baseURL.appendingPathComponent(name, isDirectory: true),
                    objectType: objectType,
                    allocatedSize: 0
                ),
                entryLength: length,
                skip: true
            )
        }

        if name == "." || name == ".." || name.isEmpty {
            return ParsedEntry(
                entry: BulkDirectoryEntry(
                    name: name,
                    url: baseURL,
                    objectType: objectType,
                    allocatedSize: 0
                ),
                entryLength: length,
                skip: true
            )
        }

        if objectType == numericObjectType(VLNK) {
            return ParsedEntry(
                entry: BulkDirectoryEntry(
                    name: name,
                    url: baseURL.appendingPathComponent(name),
                    objectType: objectType,
                    allocatedSize: 0
                ),
                entryLength: length,
                skip: true
            )
        }

        let isDirectory = objectType == numericObjectType(VDIR)
        let childURL = baseURL.appendingPathComponent(name, isDirectory: isDirectory)

        return ParsedEntry(
            entry: BulkDirectoryEntry(
                name: name,
                url: childURL,
                objectType: objectType,
                allocatedSize: allocatedSize
            ),
            entryLength: length,
            skip: false
        )
    }
}
