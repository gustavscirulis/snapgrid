import { app, BrowserWindow, ipcMain, dialog, shell, protocol, Menu, nativeImage } from 'electron';
import path from 'path';
import { fileURLToPath } from 'url';
import { createRequire } from 'module';
import fs from 'fs-extra';
import os from 'os';
import {promises as fsPromises} from 'fs'; // Import fsPromises
import chokidar from 'chokidar';

// electron-updater is CJS, so we use createRequire to import it in ESM context
const _require = createRequire(import.meta.url);
const { autoUpdater } = _require('electron-updater');
// We'll use dynamic import for electron-window-state instead
// import windowStateKeeper from 'electron-window-state';

// Get the directory name of the current module
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Detect development mode without using electron-is-dev
const isDev = process.env.NODE_ENV === 'development' || !/[\\/]app\.asar[\\/]/.test(__dirname);

// Thumbnail generation constants
const THUMB_MAX_WIDTH = 800;
const THUMB_JPEG_QUALITY = 90;

/**
 * Generates a JPEG thumbnail from an image buffer.
 * Resizes to max THUMB_MAX_WIDTH wide (preserving aspect ratio) and compresses as JPEG.
 * @param {Buffer} sourceBuffer - The original image buffer
 * @param {string} destPath - Where to write the thumbnail
 */
async function generateThumbnail(sourceBuffer, destPath) {
  if (!sourceBuffer || sourceBuffer.length === 0) {
    throw new Error('Empty or missing source buffer');
  }

  const image = nativeImage.createFromBuffer(sourceBuffer);
  if (image.isEmpty()) {
    throw new Error(`nativeImage could not decode buffer (${sourceBuffer.length} bytes)`);
  }

  const { width, height } = image.getSize();
  let resized = image;

  if (width > THUMB_MAX_WIDTH) {
    const newHeight = Math.round((THUMB_MAX_WIDTH / width) * height);
    resized = image.resize({ width: THUMB_MAX_WIDTH, height: newHeight, quality: 'best' });
  }

  const jpegBuffer = resized.toJPEG(THUMB_JPEG_QUALITY);
  await fs.writeFile(destPath, jpegBuffer);
}

/**
 * Generates missing thumbnails for existing images on startup.
 * Idempotent: skips images that already have thumbnails.
 */
async function generateMissingThumbnails(storageDir) {
  const imagesDir = path.join(storageDir, 'images');
  const thumbnailsDir = path.join(storageDir, 'thumbnails');

  try {
    const files = await fs.readdir(imagesDir);
    const imageFiles = files.filter(f => !f.startsWith('vid_') && !f.startsWith('.'));

    let generated = 0;
    let skipped = 0;
    for (const file of imageFiles) {
      const id = path.basename(file, path.extname(file));
      const thumbnailPath = path.join(thumbnailsDir, `${id}.jpg`);

      if (await fs.pathExists(thumbnailPath)) continue;

      try {
        const filePath = path.join(imagesDir, file);
        const sourceBuffer = await fs.readFile(filePath);
        await generateThumbnail(sourceBuffer, thumbnailPath);
        generated++;
      } catch (err) {
        // nativeImage can't decode WebP or other unsupported formats — skip silently
        // These files will use the original as their grid image (no thumbnail)
        skipped++;
      }
    }

    if (generated > 0 || skipped > 0) {
      console.log(`Thumbnails: ${generated} generated, ${skipped} skipped (unsupported format)`);
    }
  } catch (error) {
    console.error('Error generating missing thumbnails:', error);
  }
}

// Global storage path that will be exposed to the renderer
let appStorageDir;
let trashDir;
let mainWindow;

// Analytics preferences store
const analyticsPreferences = {
  consentGiven: true, // Default to true (opt-out model)
  
  // Get the file path for storing analytics preferences
  get filePath() {
    return path.join(app.getPath('userData'), 'analytics-preferences.json');
  },
  
  // Load preferences from disk
  load() {
    try {
      if (fs.existsSync(this.filePath)) {
        const data = fs.readFileSync(this.filePath, 'utf8');
        const prefs = JSON.parse(data);
        this.consentGiven = prefs.consentGiven ?? true;
        console.log('Loaded analytics preferences, consent:', this.consentGiven);
      } else {
        console.log('No analytics preferences file found, using default consent:', this.consentGiven);
      }
    } catch (error) {
      console.error('Error loading analytics preferences:', error);
    }
  },
  
  // Save preferences to disk
  save() {
    try {
      fs.writeFileSync(this.filePath, JSON.stringify({ consentGiven: this.consentGiven }), 'utf8');
      console.log('Saved analytics preferences, consent:', this.consentGiven);
    } catch (error) {
      console.error('Error saving analytics preferences:', error);
    }
  },
  
  // Get current consent status
  getConsent() {
    return this.consentGiven;
  },
  
  // Update consent status
  setConsent(consent) {
    this.consentGiven = !!consent;
    this.save();
    return this.consentGiven;
  }
};

// Simple API key storage with basic persistence
const apiKeyStorage = {
  keys: new Map(),
  initialized: false,
  
  // Storage file path
  get filePath() {
    return path.join(app.getPath('userData'), 'api-keys.json');
  },
  
  // Load stored keys from disk
  init() {
    if (this.initialized) return;
    
    try {
      if (fs.existsSync(this.filePath)) {
        const data = fs.readFileSync(this.filePath, 'utf8');
        const keyData = JSON.parse(data);
        
        // Convert back from object to Map
        Object.entries(keyData).forEach(([service, key]) => {
          this.keys.set(service, key);
        });
        
        console.log('API keys loaded from disk');
      }
    } catch (error) {
      console.error('Error loading API keys from disk:', error);
    }
    
    this.initialized = true;
  },
  
  // Save keys to disk
  save() {
    try {
      // Convert Map to object for JSON serialization
      const keyData = {};
      this.keys.forEach((value, key) => {
        keyData[key] = value;
      });
      
      fs.writeFileSync(this.filePath, JSON.stringify(keyData, null, 2), 'utf8');
    } catch (error) {
      console.error('Error saving API keys to disk:', error);
    }
  },
  
  setApiKey(service, key) {
    if (!service || !key) return false;
    try {
      this.init();
      this.keys.set(service, key);
      this.save();
      return true;
    } catch (error) {
      console.error(`Error storing API key for ${service}:`, error);
      return false;
    }
  },
  
  getApiKey(service) {
    if (!service) return null;
    try {
      this.init();
      return this.keys.get(service) || null;
    } catch (error) {
      console.error(`Error retrieving API key for ${service}:`, error);
      return null;
    }
  },
  
  hasApiKey(service) {
    this.init();
    return this.keys.has(service);
  },
  
  deleteApiKey(service) {
    if (!service) return false;
    try {
      this.init();
      const result = this.keys.delete(service);
      if (result) this.save();
      return result;
    } catch (error) {
      console.error(`Error deleting API key for ${service}:`, error);
      return false;
    }
  }
};

// Determine app storage directory in iCloud or local folder
const getAppStorageDir = async () => {
  const platform = process.platform;
  let storageDir;

  if (platform === 'darwin') {
    // On macOS, try to use Documents folder first for visibility
    const homeDir = os.homedir();
    storageDir = path.join(homeDir, 'Documents', 'SnapGrid');
    console.log('Using Documents folder path:', storageDir);

    // Create a README file to help users find the folder
    const readmePath = path.join(storageDir, 'README.txt');
    if (!fs.existsSync(readmePath)) {
      fs.ensureDirSync(storageDir);
      fs.writeFileSync(
        readmePath, 
        'This folder contains your SnapGrid app images and data.\n' +
        'Files are stored in the images/ directory with metadata in the metadata/ directory.\n\n' +
        'Storage location: ' + storageDir
      );
    }
  } else {
    // For other platforms, use app.getPath('userData')
    storageDir = path.join(app.getPath('userData'), 'storage');
    console.log('Using userData path:', storageDir);
  }

  // Ensure main directory exists
  fs.ensureDirSync(storageDir);

  // Create images, metadata, and thumbnails subdirectories
  const imagesDir = path.join(storageDir, 'images');
  const metadataDir = path.join(storageDir, 'metadata');
  const thumbnailsDir = path.join(storageDir, 'thumbnails');
  fs.ensureDirSync(imagesDir);
  fs.ensureDirSync(metadataDir);
  fs.ensureDirSync(thumbnailsDir);

  // Create trash directory
  trashDir = path.join(storageDir, '.trash');
  fs.ensureDirSync(trashDir);
  // Create trash subdirectories for images, metadata, and thumbnails
  const trashImagesDir = path.join(trashDir, 'images');
  const trashMetadataDir = path.join(trashDir, 'metadata');
  const trashThumbnailsDir = path.join(trashDir, 'thumbnails');
  fs.ensureDirSync(trashImagesDir);
  fs.ensureDirSync(trashMetadataDir);
  fs.ensureDirSync(trashThumbnailsDir);

  // Empty trash on startup
  await fs.emptyDir(trashImagesDir);
  await fs.emptyDir(trashMetadataDir);
  console.log('Trash emptied on startup');

  // Create queue directory for mobile imports
  const queueDir = path.join(storageDir, 'queue');
  await fs.ensureDir(queueDir);
  console.log('Queue directories created');

  return storageDir;
};

// Track whether the current update check was triggered manually via menu
let isManualUpdateCheck = false;

// Initialize native auto-updater (electron-updater)
function initAutoUpdater() {
  if (isDev) {
    console.log('Skipping auto-updater in development mode');
    return;
  }

  autoUpdater.autoDownload = true;
  autoUpdater.autoInstallOnAppQuit = true;

  autoUpdater.on('checking-for-update', () => {
    console.log('Checking for update...');
    mainWindow?.webContents.send('updater-checking');
  });

  autoUpdater.on('update-available', (info) => {
    console.log('Update available:', info.version);
    isManualUpdateCheck = false;
    mainWindow?.webContents.send('updater-update-available', {
      version: info.version,
      releaseDate: info.releaseDate,
      releaseName: info.releaseName,
    });
  });

  autoUpdater.on('update-not-available', (info) => {
    console.log('No update available. Current version is up to date.');
    if (isManualUpdateCheck) {
      mainWindow?.webContents.send('updater-not-available');
      isManualUpdateCheck = false;
    }
  });

  autoUpdater.on('download-progress', (progress) => {
    mainWindow?.webContents.send('updater-download-progress', {
      percent: progress.percent,
      bytesPerSecond: progress.bytesPerSecond,
      transferred: progress.transferred,
      total: progress.total,
    });
  });

  autoUpdater.on('update-downloaded', (info) => {
    console.log('Update downloaded:', info.version);
    mainWindow?.webContents.send('updater-update-downloaded', {
      version: info.version,
      releaseDate: info.releaseDate,
      releaseName: info.releaseName,
    });
  });

  autoUpdater.on('error', (err) => {
    console.error('Auto-updater error:', err);
    mainWindow?.webContents.send('updater-error', err?.message || 'Unknown update error');
  });

  // Check for updates after a short delay to let the window fully load
  setTimeout(() => {
    autoUpdater.checkForUpdates().catch((err) => {
      console.error('Initial update check failed:', err);
    });
  }, 3000);
}

async function createWindow() {
  appStorageDir = await getAppStorageDir();
  await generateMissingThumbnails(appStorageDir);
  console.log('App storage directory:', appStorageDir);
  
  
  // Import windowStateKeeper dynamically
  let windowState;
  try {
    // When using dynamic import in production builds, the module resolution might be different
    // Add more robust error handling and logging
    console.log('Attempting to load electron-window-state...');
    let windowStateKeeper;
    try {
      windowStateKeeper = (await import('electron-window-state')).default;
    } catch (importError) {
      console.error('Error importing electron-window-state:', importError);
      // Try alternative import method for production
      const windowStateModule = await import('electron-window-state');
      windowStateKeeper = windowStateModule.default || windowStateModule;
      console.log('Using alternative import method for electron-window-state');
    }
    
    if (!windowStateKeeper || typeof windowStateKeeper !== 'function') {
      throw new Error('electron-window-state module did not return a valid function');
    }
    
    // Use an absolute path for the file in userData to ensure it works in production
    const userDataPath = app.getPath('userData');
    console.log('Using userData path for window state:', userDataPath);
    
    windowState = windowStateKeeper({
      defaultWidth: 1280,
      defaultHeight: 800,
      file: path.join(userDataPath, 'window-state.json')
    });
    
    console.log('Window state initialized successfully');
  } catch (err) {
    console.error('Failed to load or initialize electron-window-state:', err);
    // Provide a complete fallback with manual state persistence
    const stateFilePath = path.join(app.getPath('userData'), 'window-state.json');
    let savedState = { width: 1280, height: 800, x: undefined, y: undefined };
    
    // Try to load saved state from file
    try {
      if (fs.existsSync(stateFilePath)) {
        const data = fs.readFileSync(stateFilePath, 'utf8');
        const loadedState = JSON.parse(data);
        savedState = { ...savedState, ...loadedState };
        console.log('Loaded window state from fallback file:', savedState);
      }
    } catch (loadError) {
      console.error('Error loading window state from fallback file:', loadError);
    }
    
    // Create a full fallback implementation
    windowState = { 
      ...savedState,
      manage: () => {}, 
      saveState: (win) => {
        // Manual implementation of state saving
        try {
          if (!win || win.isDestroyed()) return;
          
          const bounds = win.getBounds();
          const isMaximized = win.isMaximized();
          const isFullScreen = win.isFullScreen();
          
          const stateToSave = {
            ...bounds,
            isMaximized,
            isFullScreen
          };
          
          fs.writeFileSync(stateFilePath, JSON.stringify(stateToSave), 'utf8');
          console.log('Saved window state using fallback method:', stateToSave);
        } catch (saveError) {
          console.error('Error saving window state in fallback method:', saveError);
        }
      }
    };
    console.log('Using fallback window state implementation');
  }

  // Create the browser window.
  mainWindow = new BrowserWindow({
    x: windowState.x,
    y: windowState.y,
    width: windowState.width,
    height: windowState.height,
    minWidth: 800,
    minHeight: 600,
    titleBarStyle: 'hidden',
    trafficLightPosition: { x: 13, y: 13 },
    backgroundColor: '#141414',
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      preload: path.join(__dirname, 'preload.cjs'),
      sandbox: false  // Required for preload to access Node APIs
    },
    icon: path.join(__dirname, '../assets/icons/icon.png')
  });

  // Let windowState manage the window state
  if (typeof windowState.manage === 'function') {
    windowState.manage(mainWindow);
  }

  // Register listeners for window state saving
  ['resize', 'move', 'close'].forEach(event => {
    mainWindow.on(event, () => {
      if (mainWindow && !mainWindow.isDestroyed() && typeof windowState.saveState === 'function') {
        // Only call saveState if it's a function
        windowState.saveState(mainWindow);
      }
    });
  });

  // In production, use file protocol with the correct path
  // In development, use localhost server with flexible port detection
  const devPort = process.env.DEV_PORT || '8080'; // Default to 8080 to match Vite's configuration
  const startUrl = isDev 
    ? `http://localhost:${devPort}` 
    : `file://${path.join(__dirname, '../dist/index.html')}`;

  console.log('Loading application from:', startUrl);

  // Add webSecurity configuration and CSP for local media playback and OpenAI API
  mainWindow.webContents.session.webRequest.onHeadersReceived((details, callback) => {
    callback({
      responseHeaders: {
        ...details.responseHeaders,
        'Content-Security-Policy': [
          "default-src 'self' 'unsafe-inline' local-file: file: data:; connect-src 'self' https://api.openai.com https://api.anthropic.com https://generativelanguage.googleapis.com https://openrouter.ai https://*.telemetrydeck.com https://nom.telemetrydeck.com https://telemetrydeck.com local-file: file: data:; script-src 'self' 'unsafe-inline' blob:; media-src 'self' local-file: file: blob: data:; img-src 'self' local-file: file: blob: data:;"
        ]
      }
    });
  });

  mainWindow.loadURL(startUrl);

  if (isDev) {
    mainWindow.webContents.openDevTools({ mode: 'detach' });
  }

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
  
  // Create the application menu
  createApplicationMenu();

  // Initialize native auto-updater
  initAutoUpdater();
}

// Create the application menu with File browsing options
function createApplicationMenu() {
  const isMac = process.platform === 'darwin';
  
  const template = [
    // App menu (macOS only)
    ...(isMac ? [{
      label: app.name,
      submenu: [
        { role: 'about' },
        {
          label: 'Check for Updates',
          click: () => {
            if (!isDev) {
              isManualUpdateCheck = true;
              autoUpdater.checkForUpdates().catch((err) => {
                isManualUpdateCheck = false;
                console.error('Manual update check failed:', err);
                mainWindow?.webContents.send('updater-error', err?.message || 'Update check failed');
              });
            } else {
              mainWindow?.webContents.send('updater-not-available');
            }
          }
        },
        { type: 'separator' },
        { 
          label: 'Preferences',
          accelerator: 'CmdOrCtrl+,',
          click: () => mainWindow?.webContents.send('open-settings')
        },
        { type: 'separator' },
        { role: 'services' },
        { type: 'separator' },
        { role: 'hide' },
        { role: 'hideOthers' },
        { role: 'unhide' },
        { type: 'separator' },
        { role: 'quit' }
      ]
    }] : []),
    
    // File menu
    {
      label: 'File',
      submenu: [
        {
          label: 'Import Image',
          accelerator: 'CmdOrCtrl+O',
          click: async () => {
            const result = await dialog.showOpenDialog(mainWindow, {
              properties: ['openFile', 'multiSelections'],
              filters: [
                { name: 'Images', extensions: ['jpg', 'jpeg', 'png', 'gif', 'webp'] },
                { name: 'Videos', extensions: ['mp4', 'webm', 'mov'] },
                { name: 'All Files', extensions: ['*'] }
              ]
            });
            
            if (!result.canceled && result.filePaths.length > 0) {
              mainWindow?.webContents.send('import-files', result.filePaths);
            }
          }
        },
        {
          label: 'Open Storage Location',
          accelerator: 'CmdOrCtrl+Shift+O',
          click: async () => {
            mainWindow?.webContents.send('open-storage-location');
            await shell.openPath(appStorageDir);
          }
        }
      ]
    },
    
    // Edit menu
    {
      label: 'Edit',
      submenu: [
        { role: 'undo' },
        { role: 'redo' },
        { type: 'separator' },
        { role: 'cut' },
        { role: 'copy' },
        { role: 'paste' },
        ...(isMac ? [
          { role: 'pasteAndMatchStyle' },
          { role: 'delete' },
          { role: 'selectAll' },
          { type: 'separator' },
          {
            label: 'Speech',
            submenu: [
              { role: 'startSpeaking' },
              { role: 'stopSpeaking' }
            ]
          }
        ] : [
          { role: 'delete' },
          { type: 'separator' },
          { role: 'selectAll' }
        ])
      ]
    },
    
    // View menu
    {
      label: 'View',
      submenu: [
        { role: 'reload' },
        { role: 'forceReload' },
        { role: 'toggleDevTools' },
        { type: 'separator' },
        { role: 'resetZoom' },
        { role: 'zoomIn' },
        { role: 'zoomOut' },
        { type: 'separator' },
        { role: 'togglefullscreen' }
      ]
    },
    
    // Window menu
    {
      label: 'Window',
      submenu: [
        { role: 'minimize' },
        { role: 'zoom' },
        ...(isMac ? [
          { type: 'separator' },
          { role: 'front' },
          { type: 'separator' },
          { role: 'window' }
        ] : [
          { role: 'close' }
        ])
      ]
    },
    
    // Help menu
    {
      role: 'help',
      submenu: [
        {
          label: 'Learn More',
          click: async () => {
            await shell.openExternal('https://github.com/snapgrid');
          }
        }
      ]
    }
  ];
  
  const menu = Menu.buildFromTemplate(template);
  Menu.setApplicationMenu(menu);
}

app.whenReady().then(() => {
  // Register custom protocol to serve local files
  protocol.registerFileProtocol('local-file', (request, callback) => {
    const url = request.url.replace('local-file://', '');
    try {
      const filePath = decodeURI(url);
      const ext = path.extname(filePath).toLowerCase();
      
      // Set appropriate MIME type based on file extension
      let mimeType = 'application/octet-stream';
      if (ext === '.mp4') {
        mimeType = 'video/mp4';
      } else if (ext === '.webm') {
        mimeType = 'video/webm';
      } else if (ext === '.png') {
        mimeType = 'image/png';
      } else if (ext === '.jpg' || ext === '.jpeg') {
        mimeType = 'image/jpeg';
      }
      
      return callback({
        path: filePath,
        headers: {
          'Content-Type': mimeType,
          'Access-Control-Allow-Origin': '*'
        }
      });
    } catch (error) {
      console.error('Error with protocol handler:', error);
    }
  });

  analyticsPreferences.load();
  createWindow();
  
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

// Handle window control events
ipcMain.on('window-minimize', () => {
  if (mainWindow) mainWindow.minimize();
});

ipcMain.on('window-maximize', () => {
  if (mainWindow) {
    if (mainWindow.isMaximized()) {
      mainWindow.unmaximize();
    } else {
      mainWindow.maximize();
    }
  }
});

ipcMain.on('window-close', () => {
  if (mainWindow) mainWindow.close();
});

// Handle drag-out-of-app: initiate native file drag
ipcMain.on('start-drag', (event, { filePath, iconPath, displayName }) => {
  try {
    // If a display name is provided, copy to a temp file with that name
    let dragFilePath = filePath;
    if (displayName) {
      const ext = path.extname(filePath);
      const sanitized = displayName.replace(/[/\\?%*:|"<>]/g, '-').substring(0, 100);
      const tempDir = path.join(os.tmpdir(), 'snapgrid-drag');
      fs.ensureDirSync(tempDir);
      const tempPath = path.join(tempDir, sanitized + ext);
      try {
        // Remove any old file/symlink at the destination first
        fs.removeSync(tempPath);
        // Use native copy to create a real file (not symlink/alias)
        fs.copyFileSync(filePath, tempPath);
        dragFilePath = tempPath;
      } catch (copyErr) {
        console.error('Error creating temp file for drag:', copyErr);
      }
    }

    let icon;
    if (iconPath) {
      icon = nativeImage.createFromPath(iconPath);
      const size = icon.getSize();
      if (size.width > 200) {
        icon = icon.resize({ width: 200, height: Math.round((200 / size.width) * size.height) });
      }
    }

    if (!icon || icon.isEmpty()) {
      icon = nativeImage.createFromPath(filePath);
      if (!icon.isEmpty()) {
        const size = icon.getSize();
        if (size.width > 200) {
          icon = icon.resize({ width: 200, height: Math.round((200 / size.width) * size.height) });
        }
      }
    }

    if (!icon || icon.isEmpty()) {
      icon = nativeImage.createEmpty();
    }

    event.sender.startDrag({
      file: dragFilePath,
      icon: icon,
    });
  } catch (error) {
    console.error('Error starting drag:', error);
  }
});

// Handle multi-file drag-out-of-app
ipcMain.on('start-drag-multiple', (event, { filePaths, iconPath }) => {
  try {
    let icon;
    if (iconPath) {
      icon = nativeImage.createFromPath(iconPath);
      const size = icon.getSize();
      if (size.width > 200) {
        icon = icon.resize({ width: 200, height: Math.round((200 / size.width) * size.height) });
      }
    }

    if (!icon || icon.isEmpty()) {
      if (filePaths.length > 0) {
        icon = nativeImage.createFromPath(filePaths[0]);
        if (!icon.isEmpty()) {
          const size = icon.getSize();
          if (size.width > 200) {
            icon = icon.resize({ width: 200, height: Math.round((200 / size.width) * size.height) });
          }
        }
      }
    }

    if (!icon || icon.isEmpty()) {
      icon = nativeImage.createEmpty();
    }

    event.sender.startDrag({
      files: filePaths,
      icon: icon,
    });
  } catch (error) {
    console.error('Error starting multi drag:', error);
  }
});

// Add API key management handlers
ipcMain.handle('set-api-key', async (event, { service, key }) => {
  try {
    const success = apiKeyStorage.setApiKey(service, key);
    return { success };
  } catch (error) {
    console.error('Error in set-api-key:', error);
    return { success: false, error: error.message };
  }
});

ipcMain.handle('get-api-key', async (event, { service }) => {
  try {
    const key = apiKeyStorage.getApiKey(service);
    return { success: true, key };
  } catch (error) {
    console.error('Error getting API key:', error);
    return { success: false, error: error.message };
  }
});

ipcMain.handle('has-api-key', async (event, { service }) => {
  try {
    const hasKey = apiKeyStorage.hasApiKey(service);
    return { success: true, hasKey };
  } catch (error) {
    console.error('Error checking API key existence:', error);
    return { success: false, error: error.message };
  }
});

ipcMain.handle('delete-api-key', async (event, { service }) => {
  try {
    const result = apiKeyStorage.deleteApiKey(service);
    return { success: result };
  } catch (error) {
    console.error('Error deleting API key:', error);
    return { success: false, error: error.message };
  }
});

// Proxy OpenAI API calls through the main process to avoid CORS
ipcMain.handle('call-openai', async (event, payload) => {
  try {
    const apiKey = apiKeyStorage.getApiKey('openai');
    if (!apiKey) {
      throw new Error('OpenAI API key not found');
    }

    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(payload)
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(`OpenAI API error: ${error.error?.message || 'Unknown error'}`);
    }

    return await response.json();
  } catch (error) {
    console.error('Error calling OpenAI:', error);
    throw error;
  }
});

// List available OpenAI models (for model selection in settings)
ipcMain.handle('list-openai-models', async () => {
  try {
    const apiKey = apiKeyStorage.getApiKey('openai');
    if (!apiKey) {
      throw new Error('OpenAI API key not found');
    }

    const response = await fetch('https://api.openai.com/v1/models', {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
      }
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(`OpenAI API error: ${error.error?.message || 'Unknown error'}`);
    }

    const data = await response.json();
    return { success: true, models: data.data };
  } catch (error) {
    console.error('Error listing OpenAI models:', error);
    return { success: false, error: error.message };
  }
});

// Proxy Anthropic Claude API calls through the main process to avoid CORS
ipcMain.handle('call-claude', async (event, payload) => {
  try {
    const apiKey = apiKeyStorage.getApiKey('anthropic');
    if (!apiKey) {
      throw new Error('Anthropic API key not found');
    }

    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(payload)
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(`Anthropic API error: ${error.error?.message || 'Unknown error'}`);
    }

    return await response.json();
  } catch (error) {
    console.error('Error calling Claude:', error);
    throw error;
  }
});

// List available Anthropic Claude models (for model selection in settings)
ipcMain.handle('list-claude-models', async () => {
  try {
    const apiKey = apiKeyStorage.getApiKey('anthropic');
    if (!apiKey) {
      throw new Error('Anthropic API key not found');
    }

    const response = await fetch('https://api.anthropic.com/v1/models?limit=1000', {
      method: 'GET',
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      }
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(`Anthropic API error: ${error.error?.message || 'Unknown error'}`);
    }

    const data = await response.json();
    return { success: true, models: data.data };
  } catch (error) {
    console.error('Error listing Claude models:', error);
    return { success: false, error: error.message };
  }
});

// Proxy Google Gemini API calls through the main process to avoid CORS
ipcMain.handle('call-gemini', async (event, payload) => {
  try {
    const apiKey = apiKeyStorage.getApiKey('gemini');
    if (!apiKey) {
      throw new Error('Gemini API key not found');
    }

    const { model, ...body } = payload;

    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      }
    );

    if (!response.ok) {
      const error = await response.json();
      throw new Error(`Gemini API error: ${error.error?.message || 'Unknown error'}`);
    }

    return await response.json();
  } catch (error) {
    console.error('Error calling Gemini:', error);
    throw error;
  }
});

// List available Google Gemini models (for model selection in settings)
ipcMain.handle('list-gemini-models', async () => {
  try {
    const apiKey = apiKeyStorage.getApiKey('gemini');
    if (!apiKey) {
      throw new Error('Gemini API key not found');
    }

    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models?key=${apiKey}`,
      { method: 'GET' }
    );

    if (!response.ok) {
      const error = await response.json();
      throw new Error(`Gemini API error: ${error.error?.message || 'Unknown error'}`);
    }

    const data = await response.json();
    const models = (data.models || []).map((m) => ({
      id: m.name.replace('models/', ''),
      display_name: m.displayName,
    }));
    return { success: true, models };
  } catch (error) {
    console.error('Error listing Gemini models:', error);
    return { success: false, error: error.message };
  }
});

// Proxy OpenRouter API calls through the main process to avoid CORS
ipcMain.handle('call-openrouter', async (event, payload) => {
  try {
    const apiKey = apiKeyStorage.getApiKey('openrouter');
    if (!apiKey) {
      throw new Error('OpenRouter API key not found');
    }

    const response = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://snapgrid.app',
        'X-Title': 'SnapGrid'
      },
      body: JSON.stringify(payload)
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(`OpenRouter API error: ${error.error?.message || 'Unknown error'}`);
    }

    return await response.json();
  } catch (error) {
    console.error('Error calling OpenRouter:', error);
    throw error;
  }
});

// List available OpenRouter models filtered to vision-capable ones
ipcMain.handle('list-openrouter-models', async () => {
  try {
    const apiKey = apiKeyStorage.getApiKey('openrouter');
    if (!apiKey) {
      throw new Error('OpenRouter API key not found');
    }

    const response = await fetch('https://openrouter.ai/api/v1/models', {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'HTTP-Referer': 'https://snapgrid.app',
        'X-Title': 'SnapGrid'
      }
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(`OpenRouter API error: ${error.error?.message || 'Unknown error'}`);
    }

    const data = await response.json();
    const models = (data.data || [])
      .filter((m) => {
        const modalities = m.architecture?.input_modalities;
        return Array.isArray(modalities) && modalities.includes('image');
      })
      .map((m) => ({
        id: m.id,
        display_name: m.name || m.id,
      }));
    return { success: true, models };
  } catch (error) {
    console.error('Error listing OpenRouter models:', error);
    return { success: false, error: error.message };
  }
});

// IPC handlers for file system operations
ipcMain.handle('get-app-storage-dir', () => {
  return appStorageDir;
});

ipcMain.handle('get-trash-dir', () => {
  return trashDir;
});

ipcMain.handle('open-storage-dir', () => {
  return shell.openPath(appStorageDir);
});

ipcMain.handle('save-image', async (event, { id, dataUrl, metadata }) => {
  try {
    // Determine if this is a video or image based on the ID prefix or metadata
    const isVideo = id.startsWith('vid_') || metadata.type === 'video';

    // Choose the appropriate file extension
    const fileExt = isVideo ? '.mp4' : '.png';

    // Destination paths
    const imagesDir = path.join(appStorageDir, 'images');
    const filePath = path.join(imagesDir, `${id}${fileExt}`);
    
    // Check if dataUrl is a file path rather than a base64 data URL
    const isFilePath = !dataUrl.startsWith('data:');
    
    if (isFilePath) {
      // Copy the file directly instead of decoding base64
      console.log(`Copying file directly from: ${dataUrl}`);
      try {
        await fs.copy(dataUrl, filePath);
      } catch (copyError) {
        console.error('Error copying file:', copyError);
        throw new Error(`Failed to copy file: ${copyError.message}`);
      }
    } else {
      // Process as base64 data URL
      // Strip data URL prefix to get base64 data
      let base64Data;
      if (isVideo) {
        base64Data = dataUrl.replace(/^data:video\/\w+;base64,/, '');
      } else {
        base64Data = dataUrl.replace(/^data:image\/\w+;base64,/, '');
      }
      const buffer = Buffer.from(base64Data, 'base64');

      // Save media file with correct extension in the images directory
      await fs.writeFile(filePath, buffer);
    }

    console.log(`Media saved to: ${filePath}`);

    // Save metadata as separate JSON file in the metadata directory
    const metadataDir = path.join(appStorageDir, 'metadata');
    const metadataPath = path.join(metadataDir, `${id}.json`);
    await fs.writeJson(metadataPath, {
      ...metadata,
      filePath: filePath, // Include actual file path in metadata
      type: isVideo ? 'video' : 'image' // Ensure type is correctly set
    });

    // Generate thumbnail for images (not videos)
    let thumbnailPath = null;
    if (!isVideo) {
      try {
        const thumbnailsDir = path.join(appStorageDir, 'thumbnails');
        thumbnailPath = path.join(thumbnailsDir, `${id}.jpg`);
        const imageBuffer = await fs.readFile(filePath);
        await generateThumbnail(imageBuffer, thumbnailPath);
        console.log(`Thumbnail generated: ${thumbnailPath}`);
      } catch (thumbError) {
        console.error('Error generating thumbnail:', thumbError);
        thumbnailPath = null; // Fall back to original if thumbnail generation fails
      }
    }

    console.log(`File is accessible`);
    return { success: true, path: filePath, thumbnailPath };
  } catch (error) {
    console.error('Error saving image:', error);
    return { success: false, error: error.message };
  }
});

// Add the missing load-images handler
ipcMain.handle('load-images', async () => {
  try {
    const metadataDir = path.join(appStorageDir, 'metadata');
    const files = await fs.readdir(metadataDir);
    const jsonFiles = files.filter(file => file.endsWith('.json'));

    const images = await Promise.all(
      jsonFiles.map(async (file) => {
        const id = path.basename(file, '.json');
        const metadataPath = path.join(metadataDir, file);

        // Check if this is a video based on id prefix
        const isVideo = id.startsWith('vid_');
        // Use appropriate extension
        const fileExt = isVideo ? '.mp4' : '.png';
        const imagesDir = path.join(appStorageDir, 'images');
        const mediaPath = path.join(imagesDir, `${id}${fileExt}`);

        try {
          // Check if both metadata and media file exist
          if (!(await fs.pathExists(mediaPath))) {
            console.warn(`Media file not found: ${mediaPath}`);
            return null;
          }

          // Load metadata
          const metadata = await fs.readJson(metadataPath);

          // Use the local-file protocol for both images and videos
          const localFileUrl = `local-file://${mediaPath}`;

          // Check for thumbnail
          const thumbnailsDir = path.join(appStorageDir, 'thumbnails');
          const thumbnailPath = path.join(thumbnailsDir, `${id}.jpg`);
          const hasThumbnail = !isVideo && await fs.pathExists(thumbnailPath);

          // Construct the media object with correct paths
          const mediaObject = {
            ...metadata,
            id,
            url: localFileUrl,
            type: isVideo ? 'video' : metadata.type || 'image',
            actualFilePath: mediaPath,
            useDirectPath: true,
            ...(hasThumbnail ? { thumbnailUrl: `local-file://${thumbnailPath}` } : {})
          };

          return mediaObject;
        } catch (err) {
          console.error(`Error loading image ${id}:`, err);
          return null;
        }
      })
    );

    // Filter out any null entries (failed loads)
    return images.filter(Boolean);
  } catch (error) {
    console.error('Error loading images:', error);
    return [];
  }
});

// Add the delete-image handler
ipcMain.handle('delete-image', async (event, id) => {
  try {
    // Determine if this is a video based on id prefix
    const isVideo = id.startsWith('vid_');
    const fileExt = isVideo ? '.mp4' : '.png';

    const imagesDir = path.join(appStorageDir, 'images');
    const metadataDir = path.join(appStorageDir, 'metadata');
    const mediaPath = path.join(imagesDir, `${id}${fileExt}`);
    const metadataPath = path.join(metadataDir, `${id}.json`);
    
    const trashImagesDir = path.join(trashDir, 'images');
    const trashMetadataDir = path.join(trashDir, 'metadata');
    const trashMediaPath = path.join(trashImagesDir, `${id}${fileExt}`);
    const trashMetadataPath = path.join(trashMetadataDir, `${id}.json`);

    // Move files to trash instead of deleting
    await fs.move(mediaPath, trashMediaPath, { overwrite: true });
    await fs.move(metadataPath, trashMetadataPath, { overwrite: true });

    // Also move thumbnail if it exists
    const thumbnailPath = path.join(appStorageDir, 'thumbnails', `${id}.jpg`);
    const trashThumbnailPath = path.join(trashDir, 'thumbnails', `${id}.jpg`);
    if (await fs.pathExists(thumbnailPath)) {
      await fs.move(thumbnailPath, trashThumbnailPath, { overwrite: true });
    }

    console.log(`Moved media to trash: ${trashMediaPath}`);
    return { success: true };
  } catch (error) {
    console.error('Error moving image to trash:', error);
    return { success: false, error: error.message };
  }
});

// Add restore-from-trash handler
ipcMain.handle('restore-from-trash', async (event, id) => {
  try {
    // Determine if this is a video based on id prefix
    const isVideo = id.startsWith('vid_');
    const fileExt = isVideo ? '.mp4' : '.png';

    const imagesDir = path.join(appStorageDir, 'images');
    const metadataDir = path.join(appStorageDir, 'metadata');
    const mediaPath = path.join(imagesDir, `${id}${fileExt}`);
    const metadataPath = path.join(metadataDir, `${id}.json`);
    
    const trashImagesDir = path.join(trashDir, 'images');
    const trashMetadataDir = path.join(trashDir, 'metadata');
    const trashMediaPath = path.join(trashImagesDir, `${id}${fileExt}`);
    const trashMetadataPath = path.join(trashMetadataDir, `${id}.json`);

    // Move files back from trash
    await fs.move(trashMediaPath, mediaPath, { overwrite: true });
    await fs.move(trashMetadataPath, metadataPath, { overwrite: true });

    // Also restore thumbnail if it exists in trash
    const trashThumbnailPath = path.join(trashDir, 'thumbnails', `${id}.jpg`);
    const thumbnailPath = path.join(appStorageDir, 'thumbnails', `${id}.jpg`);
    if (await fs.pathExists(trashThumbnailPath)) {
      await fs.move(trashThumbnailPath, thumbnailPath, { overwrite: true });
    }

    console.log(`Restored media from trash: ${mediaPath}`);
    return { success: true };
  } catch (error) {
    console.error('Error restoring from trash:', error);
    return { success: false, error: error.message };
  }
});

// Add empty-trash handler
ipcMain.handle('empty-trash', async () => {
  try {
    await fs.emptyDir(path.join(trashDir, 'images'));
    await fs.emptyDir(path.join(trashDir, 'metadata'));
    await fs.emptyDir(path.join(trashDir, 'thumbnails'));
    console.log('Trash emptied successfully');
    return { success: true };
  } catch (error) {
    console.error('Error emptying trash:', error);
    return { success: false, error: error.message };
  }
});

// Add list-trash handler
ipcMain.handle('list-trash', async () => {
  try {
    const trashMetadataDir = path.join(trashDir, 'metadata');
    const files = await fs.readdir(trashMetadataDir);
    const jsonFiles = files.filter(file => file.endsWith('.json'));

    const trashItems = await Promise.all(
      jsonFiles.map(async (file) => {
        const id = path.basename(file, '.json');
        const metadataPath = path.join(trashMetadataDir, file);
        const isVideo = id.startsWith('vid_');
        const fileExt = isVideo ? '.mp4' : '.png';
        const trashImagesDir = path.join(trashDir, 'images');
        const mediaPath = path.join(trashImagesDir, `${id}${fileExt}`);

        try {
          if (!(await fs.pathExists(mediaPath))) {
            // Skip missing files silently
            return null;
          }

          const metadata = await fs.readJson(metadataPath);
          const localFileUrl = `local-file://${mediaPath}`;

          // Check for thumbnail in trash
          const trashThumbnailPath = path.join(trashDir, 'thumbnails', `${id}.jpg`);
          const hasThumbnail = !isVideo && await fs.pathExists(trashThumbnailPath);

          return {
            ...metadata,
            id,
            url: localFileUrl,
            type: isVideo ? 'video' : metadata.type || 'image',
            actualFilePath: mediaPath,
            useDirectPath: true,
            ...(hasThumbnail ? { thumbnailUrl: `local-file://${trashThumbnailPath}` } : {})
          };
        } catch (err) {
          // Skip files that can't be loaded
          return null;
        }
      })
    );

    return trashItems.filter(Boolean);
  } catch (error) {
    console.error('Error listing trash:', error);
    return [];
  }
});

// Add check-file-access handler
ipcMain.handle('check-file-access', async (event, filePath) => {
  try {
    // Check if file exists and is readable
    await fsPromises.access(filePath, fsPromises.constants.R_OK);
    console.log(`File is accessible: ${filePath}`);
    return { success: true, accessible: true };
  } catch (error) {
    console.error(`File access error for ${filePath}:`, error);
    return { success: true, accessible: false, error: error.message };
  }
});

// Add open-url handler
ipcMain.handle('open-url', async (event, url) => {
  try {
    await shell.openExternal(url);
    console.log(`Opened URL in default browser: ${url}`);
    return { success: true };
  } catch (error) {
    console.error('Error opening URL:', error);
    return { success: false, error: error.message };
  }
});

// Add update-metadata handler (merges with existing metadata to prevent stale overwrites)
ipcMain.handle('update-metadata', async (event, { id, metadata }) => {
  try {
    const metadataDir = path.join(appStorageDir, 'metadata');
    const metadataPath = path.join(metadataDir, `${id}.json`);

    // Read existing metadata so concurrent writes don't clobber each other's fields
    let existing = {};
    try {
      existing = await fs.readJson(metadataPath);
    } catch (e) {
      // File doesn't exist yet — start fresh
    }

    const merged = { ...existing, ...metadata };

    // Treat explicit null values as field deletions
    for (const key of Object.keys(merged)) {
      if (merged[key] === null) {
        delete merged[key];
      }
    }

    await fs.writeJson(metadataPath, merged);
    console.log(`Updated metadata at: ${metadataPath}`);
    return { success: true };
  } catch (error) {
    console.error('Error updating metadata:', error);
    return { success: false, error: error.message };
  }
});

// Register IPC handlers for analytics consent management
ipcMain.handle('get-analytics-consent', async () => {
  try {
    const consent = analyticsPreferences.getConsent();
    console.log('Get analytics consent request, returning:', consent);
    return consent;
  } catch (error) {
    console.error('Error getting analytics consent:', error);
    return false;
  }
});

ipcMain.handle('set-analytics-consent', async (event, consent) => {
  try {
    console.log('Setting analytics consent to:', consent);
    const result = analyticsPreferences.setConsent(consent);
    console.log('Analytics consent set result:', result);
    // Notify renderer of the change
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('analytics-consent-changed', result);
    }
    return result;
  } catch (error) {
    console.error('Error setting analytics consent:', error);
    return false;
  }
});

// Install downloaded update and restart the app
ipcMain.handle('install-update', () => {
  autoUpdater.quitAndInstall();
});

// Add handlers for user preferences (thumbnail size, etc.)
const userPreferences = {
  prefs: new Map(),
  initialized: false,
  
  // Storage file path
  get filePath() {
    return path.join(app.getPath('userData'), 'user-preferences.json');
  },
  
  // Load stored preferences from disk
  init() {
    if (this.initialized) return;
    
    try {
      if (fs.existsSync(this.filePath)) {
        const data = fs.readFileSync(this.filePath, 'utf8');
        const prefData = JSON.parse(data);
        
        // Convert back from object to Map
        Object.entries(prefData).forEach(([key, value]) => {
          this.prefs.set(key, value);
        });
        
        console.log('User preferences loaded from disk');
      }
    } catch (error) {
      console.error('Error loading user preferences from disk:', error);
    }
    
    this.initialized = true;
  },
  
  // Save preferences to disk
  save() {
    try {
      // Convert Map to object for JSON serialization
      const prefData = {};
      this.prefs.forEach((value, key) => {
        prefData[key] = value;
      });
      
      fs.writeFileSync(this.filePath, JSON.stringify(prefData, null, 2), 'utf8');
    } catch (error) {
      console.error('Error saving user preferences to disk:', error);
    }
  },
  
  setPreference(key, value) {
    if (!key) return false;
    try {
      this.init();
      this.prefs.set(key, value);
      this.save();
      return true;
    } catch (error) {
      console.error(`Error storing preference ${key}:`, error);
      return false;
    }
  },
  
  getPreference(key, defaultValue = null) {
    if (!key) return defaultValue;
    try {
      this.init();
      return this.prefs.get(key) || defaultValue;
    } catch (error) {
      console.error(`Error retrieving preference ${key}:`, error);
      return defaultValue;
    }
  }
};

ipcMain.handle('set-user-preference', async (event, { key, value }) => {
  try {
    const success = userPreferences.setPreference(key, value);
    return { success };
  } catch (error) {
    console.error('Error in set-user-preference:', error);
    return { success: false, error: error.message };
  }
});

ipcMain.handle('get-user-preference', async (event, { key, defaultValue }) => {
  try {
    const value = userPreferences.getPreference(key, defaultValue);
    return { success: true, value };
  } catch (error) {
    console.error('Error getting user preference:', error);
    return { success: false, error: error.message };
  }
});

// Queue management variables
let queueWatcher = null;
let queueProcessingActive = false;

// Start watching the queue folder for new images
ipcMain.handle('queue:start-watching', async () => {
  try {
    if (queueWatcher) {
      console.log('Queue watcher already running');
      return { success: true, message: 'Already watching' };
    }

    const queueDir = path.join(appStorageDir, 'queue');
    
    queueWatcher = chokidar.watch(queueDir, {
      ignored: /(^|[\/\\])\../, // ignore dotfiles
      persistent: true,
      ignoreInitial: false
    });

    queueWatcher.on('add', (filePath) => {
      console.log('New file detected in queue:', filePath);
      // Notify renderer about new queued file
      if (mainWindow) {
        mainWindow.webContents.send('queue:new-file', filePath);
      }
    });

    queueWatcher.on('error', (error) => {
      console.error('Queue watcher error:', error);
    });

    console.log('Started watching queue directory:', queueDir);
    return { success: true, message: 'Queue watching started' };
  } catch (error) {
    console.error('Error starting queue watcher:', error);
    return { success: false, error: error.message };
  }
});

// Stop watching the queue folder
ipcMain.handle('queue:stop-watching', async () => {
  try {
    if (queueWatcher) {
      await queueWatcher.close();
      queueWatcher = null;
      console.log('Queue watcher stopped');
    }
    return { success: true, message: 'Queue watching stopped' };
  } catch (error) {
    console.error('Error stopping queue watcher:', error);
    return { success: false, error: error.message };
  }
});

// Get list of files in queue
ipcMain.handle('queue:list-files', async () => {
  try {
    const queueDir = path.join(appStorageDir, 'queue');
    const files = await fs.readdir(queueDir);
    const imageFiles = files.filter(file => 
      /\.(jpg|jpeg|png|gif|webp|bmp|tiff)$/i.test(file)
    );
    
    return { 
      success: true, 
      files: imageFiles.map(file => path.join(queueDir, file))
    };
  } catch (error) {
    console.error('Error listing queue files:', error);
    return { success: false, error: error.message, files: [] };
  }
});

// Process a single queued file (move it to main library)
ipcMain.handle('queue:process-file', async (event, filePath) => {
  try {
    const queueDir = path.join(appStorageDir, 'queue');
    
    // Check if file is in queue directory
    if (!filePath.startsWith(queueDir)) {
      throw new Error('File is not in queue directory');
    }

    // Check if file exists
    if (!await fs.pathExists(filePath)) {
      throw new Error('File does not exist');
    }

    // Get file stats for the import
    const stats = await fs.stat(filePath);
    const fileName = path.basename(filePath);
    
    console.log('Processing queued file:', fileName);
    
    // Return file info for processing by renderer
    return {
      success: true,
      filePath,
      fileName,
      size: stats.size,
      modified: stats.mtime.toISOString()
    };
  } catch (error) {
    console.error('Error processing queued file:', error);
    return { success: false, error: error.message };
  }
});

// Remove processed file from queue
ipcMain.handle('queue:remove-file', async (event, filePath) => {
  try {
    const queueDir = path.join(appStorageDir, 'queue');

    // Check if file is in queue directory
    if (!filePath.startsWith(queueDir)) {
      throw new Error('File is not in queue directory');
    }

    await fs.remove(filePath);
    console.log('Removed processed file from queue:', path.basename(filePath));

    return { success: true, message: 'File removed from queue' };
  } catch (error) {
    console.error('Error removing file from queue:', error);
    return { success: false, error: error.message };
  }
});

// Export the iOS Shortcut file to Downloads
ipcMain.handle('export-shortcut', async () => {
  try {
    const shortcutSource = path.join(__dirname, '..', 'assets', 'Save To Snapgrid.shortcut');

    if (!await fs.pathExists(shortcutSource)) {
      throw new Error('Shortcut file not found in app bundle');
    }

    const downloadsDir = app.getPath('downloads');
    const destPath = path.join(downloadsDir, 'Save To Snapgrid.shortcut');

    await fs.copy(shortcutSource, destPath, { overwrite: true });
    shell.showItemInFolder(destPath);

    return { success: true, path: destPath };
  } catch (error) {
    console.error('Error exporting shortcut:', error);
    return { success: false, error: error.message };
  }
}); 