# SnapGrid Development Context

## Project Overview

This monorepo contains three projects that share design patterns (masonry grid, AI image analysis, spaces) but have independent, platform-specific implementations:

| Project | Location | Tech Stack |
|---------|----------|------------|
| Desktop Electron app | `/electron/` + `/src/` | Electron, React, TypeScript, Vite |
| Companion iOS app | `/ios/SnapGrid/` | SwiftUI |
| Experimental native Mac app | `/SnapGrid/` | SwiftUI + SwiftData, macOS 15+ |

---

## Electron App

### Critical Architecture

**Electron + React Hybrid**
- Main Process: `/electron/main.js` (ES modules, file system, IPC)
- Renderer: React app with Vite
- Security: `contextIsolation: true`, custom `local-file://` protocol
- **NEVER use `require()` in renderer - everything via IPC**

**State Management**
- No Redux - uses modular hooks: `useImageStore()` composes `useImageCollection()`, `useImageAnalysis()`, `useImageFileSystem()`, `useImageQueue()`

**File Storage**
```
~/Documents/SnapGrid/
├── images/     (PNG/MP4 files)
├── metadata/   (JSON, same ID as media)
├── .trash/     (auto-emptied)
└── queue/      (mobile import, auto-watched)
```

### Key Constraints

**Router**: MUST use `HashRouter` - `BrowserRouter` breaks in Electron production

**File Handling**:
- Videos: `vid_` prefix, `.mp4` extension
- Images: no prefix, `.png` extension  
- Always save media + metadata JSON with same ID
- Handle both base64 and file paths in `save-image` IPC

**API Keys**: MUST use secure storage via IPC (`setApiKey`/`getApiKey`)

### Development Commands

```bash
npm run electron:dev    # Development (Vite + Electron)
npm run build          # Check TypeScript compilation
npm run lint           # Before committing
```

### Critical Patterns

**IPC Pattern**:
```typescript
// Preload: expose to renderer
contextBridge.exposeInMainWorld('electron', {
  method: (param) => ipcRenderer.invoke('handler', param)
});

// Main: return { success, data?, error? }
ipcMain.handle('handler', async (event, param) => { ... });
```

**File Import Flow**:
1. Add to collection (immediate UI)
2. Save to disk (IPC)  
3. Analyze with AI (if API key exists)
4. Update with results

**Electron Detection**:
```typescript
const isElectron = window?.electron && typeof window.electron !== 'undefined';
```

### Essential Dependencies

- **electron-window-state**: Window persistence (complex dynamic import)
- **chokidar**: File watching for queue
- **@radix-ui/***: Complete UI system
- **framer-motion**: App-wide animations

---

## iOS App

Read-only companion viewer for the SnapGrid library. Shares the same `~/Documents/SnapGrid/` file structure with the desktop app via iCloud sync. No external dependencies — pure SwiftUI + native iOS frameworks.

### Architecture

**Entry point**: `ios/SnapGrid/SnapGrid/App/SnapGridApp.swift`
- `FileSystemManager` is the root `@StateObject`, injected via `.environmentObject`
- `ContentView` gates between `OnboardingView` (folder picker) and `MainView`
- Dark mode forced: `.preferredColorScheme(.dark)`

**State management**: No SwiftData or Redux — uses `ObservableObject` with `@Published` properties + `@State` in views.

**Key files**:
```
ios/SnapGrid/SnapGrid/
├── App/              SnapGridApp.swift, ContentView.swift
├── Models/           Space.swift, SnapGridItem.swift
├── Services/
│   ├── FileSystemManager.swift    # Folder access + URL bookmarks
│   ├── MetadataLoader.swift       # Progressive async item streaming
│   ├── SpacesManager.swift        # Load/derive spaces
│   ├── ThumbnailCache.swift       # Singleton, 4-concurrent loads, ImageIO downsampling
│   └── iCloudDownloadMonitor.swift # Polls every 3s for iCloud file readiness
├── Views/
│   ├── Main/         MainView.swift, SpaceTabBar.swift
│   ├── Grid/         MasonryGrid.swift, GridItemView.swift, PatternPills.swift
│   ├── Detail/       FullScreenImageOverlay.swift, ImageDetailView.swift, ZoomableImageView.swift
│   ├── Onboarding/   OnboardingView.swift
│   └── Shared/       EmptyStateView.swift
└── Extensions/       Color+SnapGrid.swift
```

### Key Constraints

**Folder access**: Uses `UIDocumentPickerViewController` + security-scoped URL bookmarks. User picks the SnapGrid folder once; bookmark is persisted in UserDefaults. `FileSystemManager.restoreAccess()` handles stale bookmarks.

**iCloud handling is critical**: Files may exist as `.icloud` placeholders. All loading code must:
- Detect `.json.icloud` / `.png.icloud` placeholder files
- Trigger downloads with `startDownloadingUbiquitousItem()`
- Wait for completion (MetadataLoader re-scans after 15s; ThumbnailCache waits up to 180s via `iCloudDownloadMonitor`)

**Thumbnail loading**: `ThumbnailCache.shared` uses a 4-concurrent semaphore, ImageIO downsampling, and NSCache (500 items / 100MB). Always use `loadImage()` for fast path or `loadImageWhenReady()` when iCloud download may be needed.

**Gesture system in FullScreenImageOverlay**: Uses a mode-locking pattern — once a gesture starts (dismiss/scroll/swipe/zoom), it locks to that mode until finger releases. Rubber-banding at zoom limits and swipe edges.

### Development

- Open `ios/SnapGrid/SnapGrid.xcodeproj` in Xcode 15.4+
- Build target: `SnapGrid` (iOS 17.0+)
- Bundle ID: `com.snapgrid.ios`
- No CocoaPods/SPM — zero external dependencies
- Team ID `HJ4HYUU2Y6` with automatic signing