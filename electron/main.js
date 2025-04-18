import { app, BrowserWindow, ipcMain, dialog, shell, protocol, Menu } from 'electron';
import path from 'path';
import { fileURLToPath } from 'url';
import fs from 'fs-extra';
import os from 'os';
import {promises as fsPromises} from 'fs'; // Import fsPromises
// We'll use dynamic import for electron-window-state instead
// import windowStateKeeper from 'electron-window-state';

// Get the directory name of the current module
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Detect development mode without using electron-is-dev
const isDev = process.env.NODE_ENV === 'development' || !/[\\/]app\.asar[\\/]/.test(__dirname);

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
const getAppStorageDir = () => {
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

  // Create images and metadata subdirectories
  const imagesDir = path.join(storageDir, 'images');
  const metadataDir = path.join(storageDir, 'metadata');
  fs.ensureDirSync(imagesDir);
  fs.ensureDirSync(metadataDir);

  // Create trash directory
  trashDir = path.join(storageDir, '.trash');
  fs.ensureDirSync(trashDir);
  // Create trash subdirectories for images and metadata
  const trashImagesDir = path.join(trashDir, 'images');
  const trashMetadataDir = path.join(trashDir, 'metadata');
  fs.ensureDirSync(trashImagesDir);
  fs.ensureDirSync(trashMetadataDir);

  return storageDir;
};

// Add this function before createWindow()
async function checkForUpdates() {
  try {
    // Read package.json using fs instead of require
    const packageJsonPath = path.join(path.dirname(__dirname), 'package.json');
    const packageJsonContent = await fs.readFile(packageJsonPath, 'utf-8');
    const packageJson = JSON.parse(packageJsonContent);
    const currentVersion = packageJson.version;
    
    const repoOwner = 'gustavscirulis'; // Repository owner
    const repoName = 'snapgrid'; // Repository name
    
    console.log('Checking for updates. Current version:', currentVersion);
    
    const response = await fetch(`https://api.github.com/repos/${repoOwner}/${repoName}/releases/latest`);
    
    if (!response.ok) {
      console.error('Error checking for updates:', response.status);
      return;
    }
    
    const latestRelease = await response.json();
    const latestVersion = latestRelease.tag_name.replace(/^v/, '');
    
    console.log('Latest version available:', latestVersion);
    
    // Compare versions (simple string comparison works for semver)
    if (latestVersion > currentVersion) {
      console.log('Update available!', latestRelease.name);
      
      // Notify renderer process about the update
      if (mainWindow) {
        mainWindow.webContents.send('update-available', latestRelease);
      }
    } else {
      console.log('No updates available');
    }
  } catch (error) {
    console.error('Failed to check for updates:', error);
  }
}

async function createWindow() {
  appStorageDir = getAppStorageDir();
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
    backgroundColor: '#10121A',
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
          "default-src 'self' 'unsafe-inline' local-file: file: data:; connect-src 'self' https://api.openai.com https://*.telemetrydeck.com https://nom.telemetrydeck.com https://telemetrydeck.com local-file: file: data:; script-src 'self' 'unsafe-inline' blob:; media-src 'self' local-file: file: blob: data:; img-src 'self' local-file: file: blob: data: https: http:;"
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
          click: async () => {
            await checkForUpdates();
            // If no update was found, inform the user
            if (mainWindow) {
              mainWindow.webContents.send('manual-update-check-completed');
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

app.whenReady().then(async () => {
  appStorageDir = getAppStorageDir(); // This sets trashDir
  // Automatically empty trash on app start
  if (trashDir) {
    try {
      await fs.emptyDir(path.join(trashDir, 'images'));
      await fs.emptyDir(path.join(trashDir, 'metadata'));
      console.log('Trash emptied on app start');
    } catch (error) {
      console.error('Error emptying trash on app start:', error);
    }
  }
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
  
  // Check for updates after window is created
  checkForUpdates();
  
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('before-quit', async (event) => {
  if (trashDir) {
    try {
      await fs.emptyDir(path.join(trashDir, 'images'));
      await fs.emptyDir(path.join(trashDir, 'metadata'));
      console.log('Trash emptied on app quit');
    } catch (error) {
      console.error('Error emptying trash on app quit:', error);
    }
  }
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

// Download an image from a URL and save to images dir
import fetch from 'node-fetch';
ipcMain.handle('download-image', async (event, { url, filename }) => {
  try {
    const imagesDir = path.join(appStorageDir, 'images');
    await fs.ensureDir(imagesDir);
    const filePath = path.join(imagesDir, filename);
    const res = await fetch(url);
    if (!res.ok) throw new Error(`Failed to fetch image: ${res.status}`);
    const buffer = await res.buffer();
    await fs.writeFile(filePath, buffer);
    return { success: true, filePath };
  } catch (error) {
    console.error('Error downloading image:', error);
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
    if (metadata.type === 'link') {
      // Only save metadata for link cards, no file operations
      const metadataDir = path.join(appStorageDir, 'metadata');
      const metadataPath = path.join(metadataDir, `${id}.json`);
      await fs.writeJson(metadataPath, {
        ...metadata,
        filePath: null,
        type: 'link'
      });
      console.log(`Saved link card metadata: ${metadataPath}`);
      return { success: true, path: metadataPath };
    }

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

    console.log(`File is accessible`);
    return { success: true, path: filePath };
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

        try {
          const metadata = await fs.readJson(metadataPath);

          // If it's a link card, just return the metadata (no file check)
          if (metadata.type === 'link') {
            return {
              ...metadata,
              id,
              type: 'link',
              filePath: null,
            };
          }

          // For images and videos, check for the media file
          const isVideo = id.startsWith('vid_') || metadata.type === 'video';
          const fileExt = isVideo ? '.mp4' : '.png';
          const imagesDir = path.join(appStorageDir, 'images');
          const mediaPath = path.join(imagesDir, `${id}${fileExt}`);

          if (!(await fs.pathExists(mediaPath))) {
            console.warn(`Media file not found: ${mediaPath}`);
            return null;
          }

          const localFileUrl = `local-file://${mediaPath}`;

          return {
            ...metadata,
            id,
            url: localFileUrl,
            type: isVideo ? 'video' : metadata.type || 'image',
            actualFilePath: mediaPath,
            useDirectPath: true
          };
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
    let movedAny = false;
    if (await fs.pathExists(mediaPath)) {
      await fs.move(mediaPath, trashMediaPath, { overwrite: true });
      movedAny = true;
    } else {
      console.warn(`Media file not found for deletion: ${mediaPath}`);
    }
    if (await fs.pathExists(metadataPath)) {
      // Read metadata to check for ogImageUrl and faviconUrl
      try {
        const metadata = await fs.readJson(metadataPath);
        // For link cards, check for ogImageUrl and faviconUrl
        for (const key of ['ogImageUrl', 'faviconUrl']) {
          const fileUrl = metadata[key];
          if (fileUrl && typeof fileUrl === 'string' && fileUrl.startsWith('local-file://')) {
            const localPath = fileUrl.replace('local-file://', '');
            const filename = path.basename(localPath);
            const trashPath = path.join(trashImagesDir, filename);
            if (await fs.pathExists(localPath)) {
              await fs.move(localPath, trashPath, { overwrite: true });
              console.log(`Moved ${key} to trash: ${trashPath}`);
              movedAny = true;
            } else {
              console.warn(`${key} not found for deletion: ${localPath}`);
            }
          }
        }
      } catch (metaErr) {
        console.warn(`Could not read metadata for og/fav cleanup: ${metaErr}`);
      }
      await fs.move(metadataPath, trashMetadataPath, { overwrite: true });
      movedAny = true;
    } else {
      console.warn(`Metadata file not found for deletion: ${metadataPath}`);
    }

    if (movedAny) {
      console.log(`Moved media, metadata, and/or preview images to trash for id: ${id}`);
      return { success: true };
    } else {
      console.warn(`No files found to move to trash for id: ${id}`);
      return { success: false, error: 'No files found to delete.' };
    }
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

    // --- Restore ogImageUrl and faviconUrl for link cards ---
    // Read metadata from the trash (before moving it back)
    let linkPreviewFilesRestored = false;
    if (await fs.pathExists(trashMetadataPath)) {
      try {
        const metadata = await fs.readJson(trashMetadataPath);
        for (const key of ['ogImageUrl', 'faviconUrl']) {
          const fileUrl = metadata[key];
          if (fileUrl && typeof fileUrl === 'string' && fileUrl.startsWith('local-file://')) {
            const localPath = fileUrl.replace('local-file://', '');
            const filename = path.basename(localPath);
            const trashPreviewPath = path.join(trashImagesDir, filename);
            const restoredPreviewPath = path.join(imagesDir, filename);
            if (await fs.pathExists(trashPreviewPath)) {
              await fs.move(trashPreviewPath, restoredPreviewPath, { overwrite: true });
              console.log(`Restored ${key} from trash: ${restoredPreviewPath}`);
              linkPreviewFilesRestored = true;
            } else {
              console.warn(`${key} not found in trash for restore: ${trashPreviewPath}`);
            }
          }
        }
      } catch (metaErr) {
        console.warn(`Could not read trashed metadata for og/fav restore: ${metaErr}`);
      }
    }

    // Move main media file back from trash if it exists (for images/videos)
    let mediaRestored = false;
    if (await fs.pathExists(trashMediaPath)) {
      await fs.move(trashMediaPath, mediaPath, { overwrite: true });
      mediaRestored = true;
    } else {
      console.warn(`Media file not found in trash for restore: ${trashMediaPath}`);
    }

    // Always move metadata JSON back from trash (for both images and links)
    if (await fs.pathExists(trashMetadataPath)) {
      await fs.move(trashMetadataPath, metadataPath, { overwrite: true });
    } else {
      console.warn(`Metadata file not found in trash for restore: ${trashMetadataPath}`);
    }

    console.log(`Restored${mediaRestored ? ' media,' : ''} metadata${linkPreviewFilesRestored ? ', and preview images' : ''} from trash for id: ${id}`);
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
            console.warn(`Trash media file not found: ${mediaPath}`);
            return null;
          }

          const metadata = await fs.readJson(metadataPath);
          const localFileUrl = `local-file://${mediaPath}`;

          return {
            ...metadata,
            id,
            url: localFileUrl,
            type: isVideo ? 'video' : metadata.type || 'image',
            actualFilePath: mediaPath,
            useDirectPath: true
          };
        } catch (err) {
          console.error(`Error loading trash item ${id}:`, err);
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
import https from 'https';
import { parse } from 'node-html-parser';

// ...
ipcMain.handle('fetch-link-preview', async (event, url) => {
  try {
    // Fetch HTML
    const html = await new Promise((resolve, reject) => {
      const options = {
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
        }
      };
      https.get(url, options, (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => resolve(data));
      }).on('error', reject);
    });
    // Parse HTML
    const root = parse(html);
    const ogImage = root.querySelector('meta[property="og:image"]')?.getAttribute('content');
    let favicon = root.querySelector('link[rel~="icon"]')?.getAttribute('href');
    if (favicon && !favicon.startsWith('http')) {
      try { favicon = new URL(favicon, url).href; } catch {}
    }
    const title = root.querySelector('title')?.innerText || root.querySelector('meta[property="og:title"]')?.getAttribute('content');
    const description = root.querySelector('meta[property="og:description"]')?.getAttribute('content');
    return { ogImageUrl: ogImage, faviconUrl: favicon, title, description };
  } catch (e) {
    return {};
  }
});

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

// Add update-metadata handler
ipcMain.handle('update-metadata', async (event, { id, metadata }) => {
  try {
    const metadataDir = path.join(appStorageDir, 'metadata');
    const metadataPath = path.join(metadataDir, `${id}.json`);
    await fs.writeJson(metadataPath, metadata);
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

// Add handler for manual update checks from renderer
ipcMain.handle('check-for-updates', async () => {
  await checkForUpdates();
  return { success: true };
}); 