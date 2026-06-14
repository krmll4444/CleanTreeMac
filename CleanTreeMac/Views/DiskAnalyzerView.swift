import AppKit
import SwiftUI

struct DiskAnalyzerView: View {
    @State private var viewModel = DiskAnalyzerViewModel()
    @State private var volumes = DirectoryScanner.listVolumes()

    var body: some View {
        VStack(spacing: 0) {
            topBar

            if viewModel.isScanning {
                scanningOverlay
            } else if let current = viewModel.currentNode {
                mainContent(for: current)
            } else {
                welcomeView
            }

            BasketView(
                items: viewModel.basket,
                onRemove: viewModel.removeFromBasket,
                onClear: viewModel.clearBasket,
                onDelete: viewModel.deleteBasketContents,
                onDropPath: handleDropPath
            )
        }
        .background(AppTheme.windowBackground)
        .preferredColorScheme(.light)
        .alert("Видалення", isPresented: $viewModel.showDeletionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.deletionMessage ?? "")
        }
        .onAppear {
            viewModel.launchInitialScan()
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Button {
                    viewModel.navigateBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!viewModel.canGoBack)
                .help("Назад")

                Button {
                    viewModel.navigateForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!viewModel.canGoForward)
                .help("Вперед")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            BreadcrumbView(breadcrumb: viewModel.breadcrumb) { index in
                viewModel.navigateToBreadcrumb(index: index)
            }

            Spacer()

            if viewModel.isExpandingFolder || viewModel.isBackgroundScanning {
                ProgressView()
                    .controlSize(.small)
            }

            if !viewModel.isScanning, viewModel.indexedFolderCount > 0 {
                Text("\(viewModel.indexedFolderCount) папок")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Menu {
                Button("Macintosh HD") {
                    viewModel.scanSystemDisk()
                }
                Button("Домашня папка") {
                    viewModel.scanHomeDirectory()
                }
                Button("Обрати папку…") {
                    viewModel.pickFolderToScan()
                }
                Divider()
                ForEach(volumes, id: \.path) { volume in
                    Button(SystemPaths.displayName(for: volume)) {
                        viewModel.scanVolume(volume)
                    }
                }
            } label: {
                Label("Сканувати", systemImage: "arrow.clockwise")
            }
            .menuStyle(.borderlessButton)
        }
        .background(AppTheme.barBackground)
    }

    private func mainContent(for current: FileNode) -> some View {
        HStack(spacing: 0) {
            SunburstChartView(
                items: viewModel.displayItems,
                totalSize: current.size,
                centerTitle: current.name,
                hoveredNodeID: viewModel.hoveredNodeID,
                onHover: { viewModel.hoveredNodeID = $0 },
                onSelect: { item in
                    if item.node.kind == .hiddenSpace || item.isFooter { return }
                    if item.node.isDirectory || item.isGroupedSmall {
                        viewModel.navigateInto(item.node, isGroupedSmall: item.isGroupedSmall)
                    } else {
                        viewModel.addToBasket(item.node)
                    }
                }
            )
            .frame(minWidth: 380)
            .padding(24)
            .background(AppTheme.panelBackground)

            Divider()

            FileListView(
                items: viewModel.displayItems,
                footerItems: viewModel.footerDisplayItems,
                hoveredNodeID: viewModel.hoveredNodeID,
                onHover: { viewModel.hoveredNodeID = $0 },
                onSelect: { item in
                    viewModel.navigateInto(item.node, isGroupedSmall: item.isGroupedSmall)
                },
                onAddToBasket: { item in
                    viewModel.addToBasket(item.node, isGroupedSmall: item.isGroupedSmall)
                }
            )
            .frame(minWidth: 280, maxWidth: 360)
            .background(AppTheme.panelBackground)
        }
    }

    private var scanningOverlay: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Аналіз диска…")
                .font(.headline)
            Text(viewModel.scanStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if viewModel.indexedFolderCount > 0 {
                Text("Знайдено \(viewModel.indexedFolderCount) папок")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.panelBackground)
    }

    private var welcomeView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
            Text("CleanTreeMac")
                .font(.largeTitle.bold())
            Text("Запуск аналізу Macintosh HD…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.panelBackground)
    }

    private func handleDropPath(_ path: String) {
        let url = URL(fileURLWithPath: path)
        if let node = viewModel.currentNode, let found = findNode(at: url, in: node) {
            viewModel.addToBasket(found)
        } else if FileManager.default.fileExists(atPath: path) {
            let size = (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?
                .totalFileAllocatedSize ?? 0
            let node = FileNode(
                name: url.lastPathComponent,
                url: url,
                size: Int64(size),
                isDirectory: (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            )
            viewModel.addToBasket(node)
        }
    }

    private func findNode(at url: URL, in node: FileNode) -> FileNode? {
        if node.url.standardizedFileURL == url.standardizedFileURL { return node }
        for child in node.children {
            if let found = findNode(at: url, in: child) { return found }
        }
        return nil
    }
}

#Preview {
    DiskAnalyzerView()
        .frame(width: 900, height: 600)
}
