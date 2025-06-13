# SnapGrid Development Context

## Critical Architecture

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

## Key Constraints

**Router**: MUST use `HashRouter` - `BrowserRouter` breaks in Electron production

**File Handling**:
- Videos: `vid_` prefix, `.mp4` extension
- Images: no prefix, `.png` extension  
- Always save media + metadata JSON with same ID
- Handle both base64 and file paths in `save-image` IPC

**API Keys**: MUST use secure storage via IPC (`setApiKey`/`getApiKey`)

## Development Commands

```bash
npm run electron:dev    # Development (Vite + Electron)
npm run build          # Check TypeScript compilation
npm run lint           # Before committing
```

## Critical Patterns

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

## Essential Dependencies

- **electron-window-state**: Window persistence (complex dynamic import)
- **chokidar**: File watching for queue
- **@radix-ui/***: Complete UI system
- **framer-motion**: App-wide animations