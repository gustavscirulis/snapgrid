# SnapGrid

Visual media library app for collecting screenshots and videos, with AI-powered pattern analysis. Three platform-specific apps share the same `~/Documents/SnapGrid/` storage.

| Project | Location | Stack |
|---------|----------|-------|
| Native Mac app (primary) | `/SnapGrid/` | SwiftUI + SwiftData, macOS 15+ |
| iOS companion app | `/ios/SnapGrid/` | SwiftUI + SwiftData, iOS 17+ |
| Legacy Electron app | `/electron/` + `/src/` | Electron, React, TypeScript, Vite |

The Mac app is the reference implementation. iOS matches its patterns. The Electron app is legacy.

## Shared file storage

All apps read/write the same structure. iOS syncs via iCloud.

```
~/Documents/SnapGrid/
├── images/     (media files: {id}.png, {id}.mp4, etc.)
├── metadata/   (sidecar JSON: {id}.json — same ID as media)
├── thumbnails/ (generated: {id}.jpg)
├── spaces.json (space definitions + guidance config)
├── .trash/     (auto-emptied after 30 days)
└── queue/      (mobile import staging, auto-watched by Mac)
```

## Electron app (legacy)

MUST use `HashRouter` — `BrowserRouter` breaks in Electron production.
NEVER use `require()` in renderer — all communication via IPC (`electron/preload.cjs`).

```bash
npm run electron:dev    # Development
npm run build          # TypeScript check
npm run lint           # Before committing
```

## iOS app

Syncs media and spaces via iCloud. Can run AI analysis and write results back to sidecars. Zero external dependencies.

**iCloud handling is critical** — files may exist as `.icloud` placeholders. All loading code must detect placeholders, trigger downloads with `startDownloadingUbiquitousItem()`, and wait for completion.

**Folder access** uses security-scoped URL bookmarks via `FileSystemManager`. User picks the SnapGrid folder once on first launch.

**FullScreenImageOverlay gestures** use a mode-locking pattern (dismiss/scroll/swipe/zoom lock on first touch). Respect this when modifying gesture code.

Bundle ID: `com.snapgrid.ios`.

## Mac app

Uses XcodeGen — run `cd SnapGrid && xcodegen generate` after adding/removing Swift files.

Bundle ID: `com.snapgrid.app`.

## Architecture patterns

**iOS AppState**: UI state lives in `AppState` (`@Observable @MainActor`), not scattered `@State` on views. Match this pattern for new state.

**Analysis coordination**: AI analysis logic lives in `AnalysisCoordinator` (iOS) and `ImportService` (Mac), NOT in views.

**Sidecar writes**: ALL sidecar JSON mutations go through `SidecarWriteService` (iOS) or `MetadataSidecarService` (Mac). NEVER write sidecar JSON directly in views.

**Supported media types**: Use `SupportedMedia` enum (Mac) for file extensions and UTTypes. Don't define inline extension sets.

**SwiftData saves**: Use `modelContext.saveOrLog()` (not `try? modelContext.save()`). The `saveOrLog()` extension logs errors and asserts in DEBUG to prevent silent data loss.

**`isAnalyzing` is transient** — it's persisted on `MediaItem` but represents in-flight state. Both apps reset stuck flags on launch. Don't add more persisted transient flags; track ephemeral state on coordinators instead.

## Testing

Both native apps use Swift Testing (`import Testing`, `@Test`, `@Suite`, `#expect`). Do NOT use XCTest for new tests. Tests run via pre-commit hook.

```bash
# Mac tests
cd SnapGrid && xcodegen generate && xcodebuild test -project SnapGrid.xcodeproj -scheme SnapGrid -destination 'platform=macOS'

# iOS tests
cd ios/SnapGrid && xcodebuild test -project SnapGrid.xcodeproj -scheme SnapGrid -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

**SwiftData tests** use in-memory containers via `TestContainer.create()` — never touch the real database.

**Access levels:** Change `private` to `internal` (Swift default) to make methods testable. Use `@testable import SnapGrid`.

## Common gotchas

- Check `@Environment(\.accessibilityReduceMotion)` / `UIAccessibility.isReduceMotionEnabled` before spring animations or shimmer effects
- Use `.glassEffect` on macOS 26+ / iOS 26+ with `.ultraThinMaterial` fallback for older versions
- Menu bar commands use `NotificationCenter` to communicate with `ContentView` — add new notifications in `SnapGridApp.swift`
- `NSWindow.allowsAutomaticWindowTabbing = false` — native tab bar is disabled; the app has its own Spaces tab bar
