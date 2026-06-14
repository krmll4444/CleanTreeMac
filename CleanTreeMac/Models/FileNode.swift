import Foundation

struct FileNode: Identifiable, Hashable, Sendable {
    enum Kind: Equatable, Sendable {
        case folder
        case groupedSmall
        case hiddenSpace
        case freeSpace
        case freeAndPurgeable
    }

    let id: UUID
    let name: String
    let url: URL
    let size: Int64
    let isDirectory: Bool
    var children: [FileNode]
    var kind: Kind

    init(
        id: UUID = UUID(),
        name: String,
        url: URL,
        size: Int64,
        isDirectory: Bool,
        children: [FileNode] = [],
        kind: Kind = .folder
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.size = size
        self.isDirectory = isDirectory
        self.children = children
        self.kind = kind
    }

    var isNavigable: Bool {
        kind == .folder || kind == .groupedSmall
    }

    var sortedChildren: [FileNode] {
        children.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }
            if lhs.displaySize != rhs.displaySize {
                return lhs.displaySize > rhs.displaySize
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var displaySize: Int64 {
        if isDirectory && size == 0 && kind == .folder { return 1 }
        return size
    }

    var sizeLabel: String {
        if kind == .freeAndPurgeable {
            return "~\(ByteFormat.string(for: size))"
        }
        if isDirectory && size == 0 && kind == .folder {
            return "—"
        }
        return ByteFormat.string(for: size)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs.id == rhs.id
    }
}

struct DisplayItem: Identifiable {
    let id: UUID
    let node: FileNode
    let colorIndex: Int
    let isGroupedSmall: Bool
    let isFooter: Bool

    init(
        node: FileNode,
        colorIndex: Int,
        isGroupedSmall: Bool = false,
        isFooter: Bool = false
    ) {
        self.id = node.id
        self.node = node
        self.colorIndex = colorIndex
        self.isGroupedSmall = isGroupedSmall
        self.isFooter = isFooter
    }
}

struct BasketItem: Identifiable, Hashable {
    let id: UUID
    let name: String
    let url: URL
    let size: Int64

    init(from node: FileNode) {
        self.id = UUID()
        self.name = node.name
        self.url = node.url
        self.size = node.size
    }
}
