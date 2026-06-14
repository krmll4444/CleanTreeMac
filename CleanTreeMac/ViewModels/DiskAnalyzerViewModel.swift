import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@Observable
@MainActor
final class DiskAnalyzerViewModel {
    var currentNode: FileNode?
    var breadcrumb: [FileNode] = []
    var basket: [BasketItem] = []
    var isScanning = false
    var scanStatus = "Підготовка…"
    var scanError: String?
    var hoveredNodeID: UUID?
    var deletionMessage: String?
    var showDeletionAlert = false
    var isExpandingFolder = false
    var isBackgroundScanning = false
    var indexedFolderCount = 0
    var scanProgress: Double = 0
    var scanLogLines: [ScanLogEntry] = []

    var canGoBack = false
    var canGoForward = false

    private var diskIndex = DiskIndex()
    private var historyPaths: [URL] = []
    private var historyIndex = 0
    private let smallObjectThreshold = 0.005

    var displayItems: [DisplayItem] {
        guard let currentNode else { return [] }

        if currentNode.url.path == "/" {
            return currentNode.children.enumerated().map { index, child in
                DisplayItem(
                    node: child,
                    colorIndex: chartColorIndex(for: child, fallback: index),
                    isGroupedSmall: child.kind == .groupedSmall
                )
            }
        }

        let children = currentNode.sortedChildren.filter { $0.isDirectory || $0.size > 0 }
        guard !children.isEmpty else { return [] }

        let total = children.reduce(Int64(0)) { $0 + $1.displaySize }
        var items: [DisplayItem] = []
        var smallSize: Int64 = 0
        var smallNodes: [FileNode] = []
        var colorIndex = 0

        for child in children {
            let ratio = Double(child.displaySize) / Double(max(total, 1))
            if ratio < smallObjectThreshold && children.count > 8 && child.size > 0 {
                smallSize += child.displaySize
                smallNodes.append(child)
            } else {
                items.append(DisplayItem(node: child, colorIndex: colorIndex))
                colorIndex += 1
            }
        }

        if !smallNodes.isEmpty {
            let grouped = FileNode(
                name: "малі об'єкти…",
                url: currentNode.url,
                size: smallSize,
                isDirectory: true,
                children: smallNodes,
                kind: .groupedSmall
            )
            items.append(DisplayItem(node: grouped, colorIndex: -1, isGroupedSmall: true))
        }

        return items
    }

    var footerDisplayItems: [DisplayItem] {
        guard let currentNode, currentNode.url.path == "/" else { return [] }
        return DirectoryScanner.footerItems(for: currentNode).map { node in
            DisplayItem(node: node, colorIndex: -1, isFooter: true)
        }
    }

    var volumeStats: VolumeStats {
        VolumeStats.forVolume(at: SystemPaths.systemRoot)
    }

    var volumeDisplayName: String {
        SystemPaths.displayName(for: SystemPaths.systemRoot)
    }

    var showScanPanel: Bool {
        isScanning || isBackgroundScanning
    }

    private func chartColorIndex(for node: FileNode, fallback: Int) -> Int {
        switch node.kind {
        case .groupedSmall: return -1
        case .hiddenSpace: return -2
        default: return fallback
        }
    }

    func scanSystemDisk() {
        startScan(at: SystemPaths.systemRoot)
    }

    func scanHomeDirectory() {
        startScan(at: FileManager.default.homeDirectoryForCurrentUser)
    }

    func scanVolume(_ url: URL) {
        startScan(at: url)
    }

    func pickFolderToScan() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Оберіть папку для аналізу використання диска"
        panel.prompt = "Сканувати"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        startScan(at: url)
    }

    func navigateInto(_ node: FileNode, isGroupedSmall: Bool = false) {
        let grouped = isGroupedSmall || node.kind == .groupedSmall
        guard node.isNavigable else { return }
        guard node.isDirectory || grouped else { return }

        if grouped {
            moveToNode(node, recordHistory: true)
            return
        }

        let resolved = resolveNode(node)

        if resolved.children.isEmpty {
            expandFolderIfNeeded(resolved)
        }

        moveToNode(resolved, recordHistory: true)
    }

    func navigateBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        syncNavigationFromHistory()
    }

    func navigateForward() {
        guard canGoForward else { return }
        historyIndex += 1
        syncNavigationFromHistory()
    }

    func navigateToBreadcrumb(index: Int) {
        guard index >= 0, index < breadcrumb.count else { return }
        let node = breadcrumb[index]
        moveToNode(node, recordHistory: true)
    }

    func addToBasket(_ node: FileNode, isGroupedSmall: Bool = false) {
        if isGroupedSmall {
            for child in node.children {
                addToBasket(child)
            }
            return
        }
        guard !basket.contains(where: { $0.url == node.url }) else { return }
        basket.append(BasketItem(from: node))
    }

    func removeFromBasket(_ item: BasketItem) {
        basket.removeAll { $0.id == item.id }
    }

    func clearBasket() {
        basket.removeAll()
    }

    func deleteBasketContents() {
        let urls = basket.map(\.url)
        let result = FileDeletionService.moveToTrash(urls: urls)
        basket.removeAll { item in result.succeeded.contains(item.url) }

        if result.failed.isEmpty {
            deletionMessage = "Переміщено в Кошик: \(result.succeeded.count) об'єкт(ів)"
        } else {
            deletionMessage = "Успішно: \(result.succeeded.count), помилок: \(result.failed.count)"
        }
        showDeletionAlert = true

        if let current = currentNode {
            startScan(at: current.url, preserveNavigation: true)
        }
    }

    private func startScan(at url: URL, preserveNavigation: Bool = false) {
        isScanning = true
        isBackgroundScanning = false
        scanError = nil
        scanProgress = 0.05
        scanLogLines.removeAll()

        let targetName = SystemPaths.displayName(for: url)
        scanStatus = "Сканування: \(targetName)…"
        appendScanLog("$ du -x -k -d 2 /  &  du -x -k -d 5 /")
        appendScanLog("→ Початок аналізу: \(targetName)")

        Task {
            let node = await DirectoryScanner.scan(url: url) { progress in
                Task { @MainActor in
                    self.indexedFolderCount = progress.scannedFolders
                    let path = SystemPaths.displayName(for: URL(fileURLWithPath: progress.currentPath))
                    self.scanStatus = "Сканування: \(path)…"
                    self.scanProgress = min(0.85, 0.15 + Double(progress.scannedFolders) / 8000)
                    self.appendScanLog("→ \(path)  (\(progress.scannedFolders) папок)")
                }
            } onPartialUpdate: { partial in
                Task { @MainActor in
                    self.scanProgress = 0.55
                    self.appendScanLog("✓ Попередні дані готові · \(partial.children.count) розділів")
                    self.applyPartialScan(partial, preserveNavigation: preserveNavigation)
                }
            }

            diskIndex.install(root: node)
            indexedFolderCount = diskIndex.folderCount
            applyScanResult(preserveNavigation: preserveNavigation, fallbackNode: node)
            isScanning = false
            isBackgroundScanning = false
            scanProgress = 1.0
            scanStatus = "Готово · \(diskIndex.folderCount) папок"
            appendScanLog("✓ Сканування завершено · \(diskIndex.folderCount) папок проіндексовано")
        }
    }

    private func appendScanLog(_ message: String) {
        scanLogLines.append(.make(message))
    }

    private func applyPartialScan(_ partial: FileNode, preserveNavigation: Bool) {
        diskIndex.install(root: partial)
        indexedFolderCount = diskIndex.folderCount
        isBackgroundScanning = true
        scanProgress = max(scanProgress, 0.6)
        appendScanLog("→ Уточнення дерева (du -d 5)…")

        if !preserveNavigation, currentNode == nil || currentNode?.url.path == "/" {
            resetNavigation(to: partial)
            isScanning = false
        } else if currentNode?.url.path == "/" {
            currentNode = partial
            isScanning = false
        }
    }

    private func applyScanResult(preserveNavigation: Bool, fallbackNode: FileNode) {
        if preserveNavigation, let current = currentNode {
            if let refreshed = diskIndex.node(at: current.url) {
                moveToNode(refreshed, recordHistory: false)
            } else {
                resetNavigation(to: fallbackNode)
            }
        } else {
            resetNavigation(to: fallbackNode)
        }
    }

    private func resetNavigation(to node: FileNode) {
        let resolved = resolveNode(node)
        currentNode = resolved
        breadcrumb = rebuildBreadcrumb(to: resolved)
        historyPaths = [resolved.url]
        historyIndex = 0
        updateHistoryFlags()
    }

    private func moveToNode(_ node: FileNode, recordHistory: Bool) {
        let resolved = resolveNode(node)
        currentNode = resolved
        breadcrumb = rebuildBreadcrumb(to: resolved)

        if recordHistory {
            if historyIndex < historyPaths.count - 1 {
                historyPaths = Array(historyPaths.prefix(historyIndex + 1))
            }

            if historyPaths.last?.standardizedFileURL != resolved.url.standardizedFileURL {
                historyPaths.append(resolved.url)
            }
            historyIndex = historyPaths.count - 1
        }

        updateHistoryFlags()
    }

    private func syncNavigationFromHistory() {
        guard historyIndex >= 0, historyIndex < historyPaths.count else { return }
        let url = historyPaths[historyIndex]
        if let node = diskIndex.node(at: url) {
            moveToNode(node, recordHistory: false)
        }
    }

    private func updateHistoryFlags() {
        canGoBack = historyIndex > 0
        canGoForward = historyIndex < historyPaths.count - 1
    }

    private func resolveNode(_ node: FileNode) -> FileNode {
        diskIndex.node(at: node.url) ?? node
    }

    private func expandFolderIfNeeded(_ node: FileNode) {
        isExpandingFolder = true

        Task {
            let expanded = await DirectoryScanner.scanFolder(at: node.url)
            diskIndex.merge(expanded)

            if let refreshed = diskIndex.node(at: node.url) {
                moveToNode(refreshed, recordHistory: false)
            }
            isExpandingFolder = false
        }
    }

    private func rebuildBreadcrumb(to target: FileNode) -> [FileNode] {
        guard let root = diskIndex.root else { return [target] }
        if let path = pathToNode(target, from: root) {
            return path
        }
        return [target]
    }

    private func pathToNode(_ target: FileNode, from node: FileNode) -> [FileNode]? {
        if node.url.standardizedFileURL == target.url.standardizedFileURL {
            return [node]
        }

        for child in node.children {
            if let path = pathToNode(target, from: child) {
                return [node] + path
            }
        }
        return nil
    }
}

extension FileNode {
    var dragPayload: String {
        url.path(percentEncoded: false)
    }
}
