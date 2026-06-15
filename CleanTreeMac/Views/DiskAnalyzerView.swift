import AppKit
import SwiftUI

struct DiskAnalyzerView: View {
    @State private var viewModel = DiskAnalyzerViewModel()
    @State private var volumes = DirectoryScanner.listVolumes()

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isShowingAnalyzer {
                analyzerContent
                    .onAppear {
                        viewModel.ensureCurrentNodeDisplayed()
                    }
            } else {
                HomeScreenView(
                    volumeName: viewModel.volumeDisplayName,
                    totalCapacity: viewModel.volumeStats.totalCapacity,
                    availableCapacity: viewModel.volumeStats.availableCapacity,
                    selectedScanPaths: viewModel.scanSettings.paths,
                    canScan: viewModel.canScanSelectedPaths,
                    isScanning: viewModel.isScanning,
                    onToggleScanPath: viewModel.toggleScanPath,
                    onScan: viewModel.launchInitialScan
                )
            }

            if viewModel.showScanPanel {
                ScanProgressPanel(
                    progress: viewModel.scanProgress,
                    logLines: viewModel.scanLogLines,
                    status: viewModel.scanStatus,
                    scanStartDate: viewModel.scanStartDate,
                    onCancel: viewModel.cancelScan
                )
            } else if viewModel.isShowingAnalyzer {
                BasketView(
                    items: viewModel.basket,
                    onRemove: viewModel.removeFromBasket,
                    onClear: viewModel.clearBasket,
                    onDelete: viewModel.deleteBasketContents,
                    onDropPath: handleDropPath
                )
            }
        }
        .background(AppTheme.windowBackground)
        .preferredColorScheme(.light)
        .alert("Видалення", isPresented: $viewModel.showDeletionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.deletionMessage ?? "")
        }
    }

    private var analyzerContent: some View {
        VStack(spacing: 0) {
            topBar

            if let current = viewModel.currentNode ?? viewModel.diskIndexRoot {
                mainContent(for: current)
            }
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

            BreadcrumbView(
                breadcrumb: viewModel.breadcrumb,
                onSelectRoot: { viewModel.navigateToDisksRoot() },
                onSelect: { viewModel.navigateToBreadcrumb(index: $0) }
            )

            Spacer()

            if viewModel.isExpandingFolder {
                ProgressView()
                    .controlSize(.small)
            }

            if !viewModel.showScanPanel, viewModel.indexedFolderCount > 0 {
                Text("\(viewModel.indexedFolderCount) папок")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Menu {
                Section {
                    ScanSettingsView(
                        selectedPaths: viewModel.scanSettings.paths,
                        isScanning: viewModel.isScanning,
                        onTogglePath: viewModel.toggleScanPath
                    )
                }

                Divider()

                Button("Macintosh HD") {
                    viewModel.scanSystemDisk()
                }
                .disabled(!viewModel.canScanSelectedPaths)
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
