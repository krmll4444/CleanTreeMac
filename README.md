# CleanTreeMac

**CleanTreeMac** is an open-source macOS app that helps you find what takes up space on your disk and clean it up safely — inspired by tools like DaisyDisk.

Visualize folder sizes with a sunburst chart, browse the file tree, drag items into a basket, and delete them to the system Trash in one click.

## Features

- **Home screen** — volume stats, configurable scan targets, manual **Сканувати** (no auto-scan on launch)
- **Sunburst chart** — folder size proportional to segment angle
- **File list** — synced hover highlighting with the chart
- **Breadcrumb + back/forward** navigation
- **Deletion basket** — drag-and-drop or double-click to queue, delete to Trash in one action
- **Configurable Macintosh HD scan** — checkboxes for home folder, `/Applications`, `/Library` (persisted in UserDefaults)
- **Parallel scanning** — one `du` process per selected path, merged progressively into the root tree
- **Scan progress panel** — live progress bar, elapsed timer, terminal-style log (copyable), cancel button
- **Detailed scan logging** — `[du]` / `[scan]` tags in Xcode console; stderr from `du` (e.g. `Permission denied`) surfaced in the UI log
- **Root layout** — priority folders, “small objects…”, “hidden space…”, free-space footer rows

## How it works

```
┌─────────────────────────────────────────────────────────────┐
│  HomeScreenView  →  DiskAnalyzerView (SwiftUI)              │
│  Sunburst · File list · Breadcrumbs · Basket · Scan panel  │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│  DiskAnalyzerViewModel (@Observable)                        │
│  Scan settings · Navigation · Basket · Scan log / cancel    │
└──────────────────────────┬──────────────────────────────────┘
                           │
         ┌─────────────────┼─────────────────┐
         ▼                 ▼                 ▼
  DirectoryScanner    DiskIndex      FileDeletionService
         │
    ┌────┴────┐
    ▼         ▼
FolderSizeCalculator   FastDirectoryScanner (fallback)
    │
    ▼
/usr/bin/du -x -k -d 4 <path>  →  parseTree  →  FileNode tree
```

### Scan pipeline

1. **Launch** — home screen shows volume name and free space; user picks scan paths and taps **Сканувати**.
2. **TCC (optional)** — `requestDocumentsAccess()` may show an `NSOpenPanel` for `~/Documents` if not already readable.
3. **Macintosh HD** — `scanMacintoshHD()` reads `ScanSettings`, runs **parallel** `du -x -k -d 4` per selected path (`~/Users` home path, `/Applications`, `/Library`).
4. **Progressive merge** — each completed path merges into the root via `DiskIndex` + `onPartialUpdate` (UI updates before all paths finish).
5. **Fallback** — if `du` fails for a path, `FastDirectoryScanner` (`getattrlistbulk`) is tried.
6. **Root layout** — children grouped into priority folders, “small objects…”, and “hidden space…”; volume stats add free-space footer rows.
7. **Drill-down** — clicking a folder uses `DiskIndex` for instant navigation; empty branches trigger `scanFolder()` (`du`, depth 4).
8. **Cancel** — terminates active `du` processes via `DUProcessRegistry` and cancels the scan `Task`.
9. **Delete** — basket items move to Trash via `FileManager.trashItem`.

### Key design choices

- **No App Sandbox** — runs with normal user permissions; `ENABLE_USER_SELECTED_FILES = readwrite` for folder picker access.
- **One `du` call per scan path** — sizes and tree structure come from parsing `du` stdout, not recursive `FileManager` walks.
- **Streaming pipe reads** — stdout/stderr from `du` are consumed while the process runs (avoids pipe-buffer deadlock on large trees).
- **`du` exit 1 is OK** — TCC often yields `Permission denied` on stderr but partial stdout is still used.
- **`DiskIndex`** — path → `FileNode` map for O(1) lookup during back/forward and breadcrumb navigation.
- **Ukrainian UI** — user-facing strings are in Ukrainian.

## Requirements

- macOS 26.2+ (Xcode project deployment target)
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
├── CleanTreeMacApp.swift              App entry
├── ContentView.swift                  Root view wrapper
├── Models/
│   ├── FileNode.swift                 Tree node, DisplayItem, BasketItem
│   └── ScanSettings.swift             UserDefaults-backed scan path selection
├── Services/
│   ├── DirectoryScanner.swift         Scan orchestration (Macintosh HD, folders)
│   ├── FolderSizeCalculator.swift   du wrapper, streaming pipes, tree parsing
│   ├── FastDirectoryScanner.swift     getattrlistbulk fallback scanner
│   ├── ScanLogger.swift               Tagged console + optional UI log forwarding
│   ├── DiskIndex.swift                Path index for navigation
│   ├── FileDeletionService.swift      Trash integration
│   └── SystemPaths.swift              Volume paths, scan defaults, localized names
├── ViewModels/
│   └── DiskAnalyzerViewModel.swift    State, navigation, scan lifecycle
├── Views/
│   ├── DiskAnalyzerView.swift         Main screen (home + analyzer modes)
│   ├── HomeScreenView.swift           Volume info + scan button + path checkboxes
│   ├── ScanProgressPanel.swift        Progress bar, timer, terminal log, cancel
│   ├── ScanSettingsView.swift         Scan path checkboxes (menu)
│   ├── SunburstChartView.swift        Chart
│   ├── FileListView.swift             Sidebar list
│   ├── BreadcrumbView.swift           Path bar
│   └── BasketView.swift               Deletion basket
└── Utilities/
    ├── AppTheme.swift                 Colors
    └── Formatters.swift               Byte formatting, scan log timestamps
```

## Privacy / Info.plist

Generated Info.plist keys (via `INFOPLIST_KEY_*` in the Xcode project):

- `NSDocumentsFolderUsageDescription`
- `NSDesktopFolderUsageDescription`
- `NSDownloadsFolderUsageDescription`

All use: *«CleanTreeMac аналізує вміст диску щоб показати використання простору»*.

## Open source

CleanTreeMac is **open source**. You are free to use, study, modify, and distribute it.

Contributions, issues, and pull requests are welcome.

## AI / agent documentation

For LLMs and coding agents, see:

- [`llms.txt`](llms.txt) — machine-readable project map
- [`AGENTS.md`](AGENTS.md) — conventions and edit guidelines for AI assistants

## Disclaimer

This app can delete files permanently (via Trash). Review basket contents before deleting. The authors are not responsible for data loss from misuse.
