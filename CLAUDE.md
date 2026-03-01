# SnapGrid

Visual media library app for collecting screenshots and videos, with AI-powered pattern analysis. Three platform-specific apps share the same `~/Documents/SnapGrid/` storage.

| Project | Location | Stack |
|---------|----------|-------|
| Desktop Electron app | `/electron/` + `/src/` | Electron, React, TypeScript, Vite |
| Companion iOS app | `/ios/SnapGrid/` | SwiftUI, iOS 17+ |
| Experimental native Mac app | `/SnapGrid/` | SwiftUI + SwiftData, macOS 15+ |

## Shared File Storage

All three apps read/write the same structure. iOS syncs via iCloud.

```
~/Documents/SnapGrid/
├── images/     (PNG/MP4 — videos use vid_ prefix)
├── metadata/   (JSON, same ID as media file)
├── .trash/     (auto-emptied)
└── queue/      (mobile import, auto-watched)
```

## Electron App

MUST use `HashRouter` — `BrowserRouter` breaks in Electron production.
NEVER use `require()` in renderer — all communication via IPC (`electron/preload.cjs`).
API keys use secure storage via IPC (`setApiKey`/`getApiKey`).
State management uses modular hooks, not Redux (see `src/hooks/`).

```bash
npm run electron:dev    # Development (Vite + Electron)
npm run build          # TypeScript check
npm run lint           # Before committing
```

## iOS App

Read-only companion viewer. Shares storage with desktop app via iCloud sync. Zero external dependencies.

**iCloud handling is critical** — files may exist as `.icloud` placeholders. All loading code must detect placeholders, trigger downloads with `startDownloadingUbiquitousItem()`, and wait for completion.

**Folder access** uses security-scoped URL bookmarks via `FileSystemManager`. User picks the SnapGrid folder once on first launch.

**FullScreenImageOverlay gestures** use a mode-locking pattern (dismiss/scroll/swipe/zoom lock on first touch). Respect this when modifying gesture code.

Open `ios/SnapGrid/SnapGrid.xcodeproj` in Xcode 15.4+. Bundle ID: `com.snapgrid.ios`.

## Mac App (Experimental)

Native SwiftUI + SwiftData rewrite. Uses XcodeGen (`SnapGrid/project.yml`).

Open `SnapGrid/SnapGrid.xcodeproj` in Xcode. Bundle ID: `com.snapgrid.app`.
