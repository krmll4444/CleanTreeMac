import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FileListView: View {
    let items: [DisplayItem]
    let footerItems: [DisplayItem]
    let hoveredNodeID: UUID?
    let onHover: (UUID?) -> Void
    let onSelect: (DisplayItem) -> Void
    let onAddToBasket: (DisplayItem) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    FileListRow(
                        item: item,
                        isHovered: hoveredNodeID == item.node.id,
                        onHover: onHover,
                        onSelect: onSelect,
                        onAddToBasket: onAddToBasket
                    )
                }

                if !footerItems.isEmpty {
                    Divider()
                        .padding(.vertical, 8)

                    ForEach(footerItems) { item in
                        FileListRow(
                            item: item,
                            isHovered: false,
                            onHover: { _ in },
                            onSelect: { _ in },
                            onAddToBasket: { _ in }
                        )
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
}

private struct FileListRow: View {
    let item: DisplayItem
    let isHovered: Bool
    let onHover: (UUID?) -> Void
    let onSelect: (DisplayItem) -> Void
    let onAddToBasket: (DisplayItem) -> Void

    private var dotColor: Color {
        if item.node.kind == .hiddenSpace {
            return .purple.opacity(0.75)
        }
        if item.isGroupedSmall {
            return AppTheme.smallSegmentFill
        }
        if item.isFooter {
            return Color.primary.opacity(0.35)
        }
        return Color(hue: ChartPalette.hue(for: max(item.colorIndex, 0)), saturation: 0.62, brightness: 0.72)
    }

    private var nameColor: Color {
        if item.node.kind == .hiddenSpace {
            return .purple
        }
        if item.isFooter {
            return .secondary
        }
        return item.node.isDirectory ? .primary : Color.primary.opacity(0.75)
    }

    private var isInteractive: Bool {
        !item.isFooter
            && item.node.kind != .hiddenSpace
            && item.node.kind != .freeSpace
            && item.node.kind != .freeAndPurgeable
    }

    private var isFileRow: Bool {
        isInteractive && !item.node.isDirectory && !item.isGroupedSmall
    }

    private var canOpenInFinder: Bool {
        isInteractive
            && !item.node.url.path.hasPrefix("/.cleantree/")
            && FileManager.default.fileExists(atPath: item.node.url.path)
    }

    var body: some View {
        HStack(spacing: 10) {
            if item.node.kind == .freeAndPurgeable {
                Text("~")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
            } else {
                Circle()
                    .fill(dotColor)
                    .frame(width: 10, height: 10)
            }

            Text(item.node.name)
                .lineLimit(1)
                .foregroundStyle(nameColor)

            Spacer()

            Text(item.node.sizeLabel)
                .foregroundStyle(item.node.size == 0 && item.node.isDirectory ? .tertiary : .secondary)
                .monospacedDigit()

            if isFileRow && isHovered {
                Image(systemName: "plus.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Додати в кошик")
            }

            if isInteractive && (item.node.isDirectory || item.isGroupedSmall) {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isHovered ? AppTheme.hoverHighlight : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            guard isInteractive else { return }
            if item.node.kind == .folder {
                onAddToBasket(item)
            } else if isFileRow {
                onAddToBasket(item)
            }
        }
        .onTapGesture {
            guard isInteractive else { return }
            if item.node.isDirectory || item.isGroupedSmall {
                onSelect(item)
            } else {
                onAddToBasket(item)
            }
        }
        .onHover { hovering in
            guard isInteractive else { return }
            onHover(hovering ? item.node.id : nil)
        }
        .contextMenu {
            if canOpenInFinder {
                Button("Open with Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([item.node.url])
                }
            }
        }
        .onDrag {
            guard item.node.kind == .folder else {
                return NSItemProvider()
            }
            return NSItemProvider(object: item.node.dragPayload as NSString)
        }
    }
}
