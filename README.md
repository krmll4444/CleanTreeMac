# CleanTreeMac

**CleanTreeMac** is an open-source macOS app that helps you find what takes up space on your disk and clean it up safely — inspired by tools like DaisyDisk.

Visualize folder sizes with a sunburst chart, browse the file tree, drag items into a basket, and delete them to the system Trash in one click.

## Features

- **Sunburst chart** — folder size proportional to segment angle
- **File list** — synced hover highlighting with the chart
- **Breadcrumb + back/forward** navigation
- **Deletion basket** — drag-and-drop or double-click to queue, delete to Trash in one action
- **Macintosh HD scan** — priority folders (Users, System, Applications, Library, private), small objects grouping, hidden space, free space footer
- **Fast scanning** — single `du` pass per stage instead of recursive FileManager walks

## How it works

```
┌─────────────────────────────────────────────────────────────┐
│  DiskAnalyzerView (SwiftUI)                                 │
│  Sunburst · File list · Breadcrumbs · Basket              │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│  DiskAnalyzerViewModel (@Observable)                        │
│  Navigation history · Display items · Basket state          │
└──────────────────────────┬──────────────────────────────────┘
                           │
         ┌─────────────────┼─────────────────┐
         ▼                 ▼                 ▼
  DirectoryScanner    DiskIndex      FileDeletionService
         │
         ▼
  FolderSizeCalculator  →  `du -x -k -d N /`  →  parseTree  →  FileNode tree
```

### Scan pipeline

1. **Launch** — `scanMacintoshHD()` runs automatically on `/` (Macintosh HD).
2. **Stage 1** — `du -x -k -d 2 /` builds a shallow tree; UI updates via `onPartialUpdate` (fast first paint).
3. **Stage 2** — `du -x -k -d 5 /` refines the tree for deeper navigation.
4. **Root layout** — children are grouped into priority folders, “small objects…”, and “hidden space…”; volume stats add free-space footer rows.
5. **Drill-down** — clicking a folder uses `DiskIndex` for instant navigation; empty branches trigger `scanFolder()` (single `du` pass, depth 4).
6. **Delete** — basket items move to Trash via `FileManager.trashItem`.

### Key design choices

- **No App Sandbox** — runs with normal user permissions (like DaisyDisk), so system folders and hidden paths are readable without Full Disk Access prompts.
- **One `du` call per scan** — sizes and tree structure come from parsing `du` stdout, not millions of `FileManager` stat calls.
- **`DiskIndex`** — path → `FileNode` map for O(1) lookup during back/forward and breadcrumb navigation.

## Requirements

- macOS 26+ (Xcode 26 project settings)
- Xcode 26+

## Build & run

```bash
git clone https://github.com/your-username/CleanTreeMac.git
cd CleanTreeMac
open CleanTreeMac.xcodeproj
```

Press **⌘R** in Xcode.

## Project structure

```
CleanTreeMac/
├── CleanTreeMacApp.swift          App entry
├── ContentView.swift              Root view wrapper
├── Models/
│   └── FileNode.swift             Tree node, DisplayItem, BasketItem
├── Services/
│   ├── DirectoryScanner.swift     Scan orchestration (Macintosh HD, folders)
│   ├── FolderSizeCalculator.swift   du wrapper + tree parsing
│   ├── DiskIndex.swift             Path index for navigation
│   ├── FileDeletionService.swift   Trash integration
│   └── SystemPaths.swift           Volume paths, localized names
├── ViewModels/
│   └── DiskAnalyzerViewModel.swift State & navigation logic
├── Views/
│   ├── DiskAnalyzerView.swift     Main screen
│   ├── SunburstChartView.swift    Chart
│   ├── FileListView.swift         Sidebar list
│   ├── BreadcrumbView.swift       Path bar
│   └── BasketView.swift           Deletion basket
└── Utilities/
    ├── AppTheme.swift             Colors
    └── Formatters.swift           Byte formatting
```

## Open source

CleanTreeMac is **open source**. You are free to use, study, modify, and distribute it.

Contributions, issues, and pull requests are welcome.

## AI / agent documentation

For LLMs and coding agents, see:

- [`llms.txt`](llms.txt) — machine-readable project map
- [`AGENTS.md`](AGENTS.md) — conventions and edit guidelines for AI assistants

## Disclaimer

This app can delete files permanently (via Trash). Review basket contents before deleting. The authors are not responsible for data loss from misuse.
