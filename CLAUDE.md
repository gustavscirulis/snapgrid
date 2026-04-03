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

## Testing (Mac & iOS)

Both native apps have Swift Testing test suites. Tests run automatically on PRs via GitHub Actions.

**When adding new features or changing existing logic, you must:**
- Write tests for any new service methods, model properties, or business logic
- Update existing tests if you change the behavior of tested functions
- Run tests locally before committing: `cd SnapGrid && xcodegen generate && xcodebuild test -project SnapGrid.xcodeproj -scheme SnapGrid -destination 'platform=macOS'`

**Test framework:** Swift Testing (`import Testing`, `@Test`, `@Suite`, `#expect`). Do NOT use XCTest for new tests.

**Test locations:** `SnapGrid/SnapGridTests/` (Mac), `ios/SnapGrid/SnapGridTests/` (iOS). Shared test helpers in `Helpers/`. Tags defined in `TestTags.swift`.

**SwiftData tests** use in-memory containers via `TestContainer.create()` — never touch the real database.

**Access levels:** If you need to test a private method, change it to `internal` (Swift's default). Use `@testable import SnapGrid` in tests.

## Apple HIG Compliance (Mac & iOS)

All native SwiftUI code must follow Apple's Human Interface Guidelines. When writing or modifying views:

**Accessibility (non-negotiable):**
- Every interactive element needs `.accessibilityLabel()` — buttons, grid items, tabs, badges
- Icon-only buttons always need a label (the icon is not enough for VoiceOver)
- Status elements (toasts, badges, progress) need `.accessibilityAddTraits(.isStatusElement)`
- Check `@Environment(\.accessibilityReduceMotion)` before applying spring animations, staggered reveals, or continuous animations (shimmer). Use `.easeInOut(duration: 0.15)` or `.identity` as fallback
- Use semantic text styles (`.headline`, `.body`, `.caption`) instead of `.system(size: N)` so text scales with Dynamic Type

**Colors & system integration:**
- Use `Color.accentColor` for selection indicators and interactive highlights — never hardcode `Color.blue`
- When defining custom adaptive colors, add Increase Contrast variants by checking `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast`
- Custom background colors are acceptable for media apps, but interactive/text colors should respect system accessibility settings

**macOS-specific patterns:**
- Settings must use `Settings {}` scene with `TabView` and `.formStyle(.grouped)`
- Provide comprehensive menu bar commands with standard keyboard shortcuts
- Support `Cmd+Click` toggle, `Shift+Click` range, and rubber band selection
- Windows should have a title (even if title bar is hidden) for Mission Control/Window menu
- Persist view state (`@AppStorage`/`@SceneStorage`) so the app restores on relaunch
