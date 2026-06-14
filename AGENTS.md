# AGENTS.md — CleanTreeMac

Guide for AI coding assistants working in this repository.

## Project summary

Open-source native macOS disk analyzer (SwiftUI). Scans via `du`, visualizes with sunburst + list, deletes via basket → Trash.

## Where to change what

| Task | Primary files |
|------|----------------|
| Scan speed / du depth | `Services/FolderSizeCalculator.swift`, `Services/DirectoryScanner.swift` |
| Macintosh HD categories | `Services/DirectoryScanner.swift` (macintoshHDRoot, buildMacintoshHDRoot) |
| Navigation / index | `Services/DiskIndex.swift`, `ViewModels/DiskAnalyzerViewModel.swift` |
| Chart / list UI | `Views/SunburstChartView.swift`, `Views/FileListView.swift` |
| Deletion | `Services/FileDeletionService.swift`, `Views/BasketView.swift` |
| Theming | `Utilities/AppTheme.swift` |

## Scan system (do not break)

1. **One du per scan stage** — `FolderSizeCalculator.fullSnapshot(path:depth:)`
2. **Parse once** — `parseTree` → `buildTree` → `FileNode`
3. **Progressive root scan** — stage d=2 partial update, then d=5 final
4. **Drill-down** — `DirectoryScanner.scanFolder(at:depth: 4)`
5. **Fallback only when du returns nil** — `fallbackFolder`

## Do not

- Spawn separate `du`/`Process` per subfolder (removed intentionally)
- Re-enable App Sandbox without user request
- Full `pathMap.removeAll()` on every DiskIndex.merge (use branch deindex)
- Change FileNode API without updating DiskIndex and ViewModel

## Do

- Match existing Swift style: enums for namespaced services, `@Observable` ViewModel
- Keep UI strings in Ukrainian where already localized
- Minimize diff scope
- Run `xcodebuild -scheme CleanTreeMac -configuration Debug build` after service-layer changes

## Testing manually

1. ⌘R in Xcode
2. Wait for Macintosh HD — Users should show GB-scale size
3. Navigate into Users → profile folder
4. Drag folder to basket → delete → confirm Trash

## Machine-readable map

See [llms.txt](llms.txt) for full architecture documentation suitable for LLM context.
