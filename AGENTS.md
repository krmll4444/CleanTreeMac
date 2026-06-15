# AGENTS.md — CleanTreeMac

Guide for AI coding assistants working in this repository.

## Project summary

Open-source native macOS disk analyzer (SwiftUI). Scans via parallel `du` per user-selected path, visualizes with sunburst + list, deletes via basket → Trash. UI strings are Ukrainian.

## Where to change what

| Task | Primary files |
|------|----------------|
| Scan speed / du depth | `Services/FolderSizeCalculator.swift`, `Services/DirectoryScanner.swift` |
| Scan path selection | `Models/ScanSettings.swift`, `Services/SystemPaths.swift`, `Views/HomeScreenView.swift` |
| Macintosh HD merge / root layout | `Services/DirectoryScanner.swift` (`scanMacintoshHD`, `MacintoshHDScanAccumulator`, `buildMacintoshHDRoot`) |
| du pipe / stderr / hang debugging | `Services/FolderSizeCalculator.swift` (`runDU`, `DUStreamCollector`) |
| Fallback scanner | `Services/FastDirectoryScanner.swift` |
| Scan logging (console + UI) | `Services/ScanLogger.swift`, `ViewModels/DiskAnalyzerViewModel.swift` |
| Scan UI (progress, cancel, log) | `Views/ScanProgressPanel.swift`, `ViewModels/DiskAnalyzerViewModel.swift` |
| TCC / Documents access | `ViewModels/DiskAnalyzerViewModel.swift` (`requestDocumentsAccess`), `project.pbxproj` (`INFOPLIST_KEY_*`) |
| Navigation / index | `Services/DiskIndex.swift`, `ViewModels/DiskAnalyzerViewModel.swift` |
| Chart / list UI | `Views/SunburstChartView.swift`, `Views/FileListView.swift` |
| Deletion | `Services/FileDeletionService.swift`, `Views/BasketView.swift` |
| Theming | `Utilities/AppTheme.swift` |

## Scan system (do not break)

1. **Manual scan only on home screen** — `launchInitialScan()` / **Сканувати**; no auto-scan on app launch
2. **Path checkboxes do not rescan** — `toggleScanPath` only saves `ScanSettings`
3. **One du per selected path** — `FolderSizeCalculator.fullSnapshot(path:depth:)` with depth **4** for Macintosh HD
4. **Parallel paths** — `scanMacintoshHD` uses `withTaskGroup`; merge after each path via `onPartialUpdate`
5. **Stream pipes while du runs** — stdout/stderr readability handlers; never block on full pipe buffer
6. **Fallback** — `FastDirectoryScanner` only when du or `buildTree` fails for that path
7. **Drill-down** — `DirectoryScanner.scanFolder(at:depth: 4)`
8. **Cancel** — `DUProcessRegistry.terminateAll()` + cancel scan `Task`
9. **du exit 1** — still use stdout when present (TCC `Permission denied` on stderr is normal)

## Do not

- Read `du` stdout only after process exit (causes pipe deadlock on large trees)
- Spawn separate `du` per subfolder during initial Macintosh HD scan
- Re-enable App Sandbox without user request
- Auto-rescan when scan path checkboxes change
- Full `pathMap.removeAll()` on every `DiskIndex.merge` (use branch deindex)
- Change `FileNode` API without updating `DiskIndex` and ViewModel
- Commit unless the user explicitly asks

## Do

- Match existing Swift style: enums for namespaced services, `@Observable` ViewModel
- Keep UI strings in Ukrainian where already localized
- Minimize diff scope
- Log via `ScanLogger` with appropriate tag (`du`, `scan`, `tree`, `merge`)
- Run `xcodebuild -scheme CleanTreeMac -configuration Debug build` after service-layer changes

## Testing manually

1. ⌘R in Xcode
2. Home screen — verify volume name and free space; toggle scan paths (no scan should start)
3. Tap **Сканувати** — progress panel appears; log shows `[du]` lines; stderr `Permission denied` may appear
4. Wait for partial then final tree — home folder / Users should show GB-scale size
5. Navigate into a folder; cancel mid-scan and confirm du processes stop
6. Drag folder to basket → delete → confirm Trash

## Machine-readable map

See [llms.txt](llms.txt) for full architecture documentation suitable for LLM context.
