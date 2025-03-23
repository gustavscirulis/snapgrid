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
      }
    } catch (error) {
      // Silent error
    }
  },
  
  // Save preferences to disk
  save() {
    try {
      fs.writeFileSync(this.filePath, JSON.stringify({ consentGiven: this.consentGiven }), 'utf8');
    } catch (error) {
      // Silent error
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

async function createWindow() {
  appStorageDir = getAppStorageDir();
  console.log('App storage directory:', appStorageDir);
  
  // Migrate existing files if needed
  await migrateFilesToNewStructure();

  // Dynamically import electron-window-state
  let windowStateKeeper;
  try {
    if (isDev) {
      // In dev mode, use the regular import
      const windowStateModule = await import('electron-window-state');
      windowStateKeeper = windowStateModule.default;
    } else {
      // In production, try to load from the extraResources path
      const windowStateModule = await import(path.join(process.resourcesPath, 'node_modules', 'electron-window-state', 'index.js'));
      windowStateKeeper = windowStateModule.default;
    }
  } catch (error) {
    console.error('Failed to load electron-window-state:', error);
    // Fallback if window state fails to load
    windowStateKeeper = (opts) => ({
      x: undefined,
      y: undefined,
      width: opts.defaultWidth,
      height: opts.defaultHeight,
      manage: () => {}
    });
  }

  // Load the window state
  const mainWindowState = windowStateKeeper({
    defaultWidth: 1200,
    defaultHeight: 800
  });

  mainWindow = new BrowserWindow({
    x: mainWindowState.x,
    y: mainWindowState.y,
    width: mainWindowState.width,
    height: mainWindowState.height,
    minWidth: 520,
    minHeight: 370,
    frame: false,
    titleBarStyle: "hidden",
    titleBarOverlay: false,
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      preload: path.join(__dirname, 'preload.cjs'),
      webSecurity: true,
      sandbox: false
    },
  });

  // Let mainWindowState manage the window state
  mainWindowState.manage(mainWindow);

  // In production, use file protocol with the correct path
  // In development, use localhost server
  const startUrl = isDev 
    ? 'http://localhost:8080' 
    : `file://${path.join(__dirname, '../dist/index.html')}`;

  console.log('Loading application from:', startUrl);

  // Add webSecurity configuration and CSP for local media playback and OpenAI API
  mainWindow.webContents.session.webRequest.onHeadersReceived((details, callback) => {
    callback({
      responseHeaders: {
        ...details.responseHeaders,
        'Content-Security-Policy': [
          "default-src 'self' 'unsafe-inline' local-file: file: data:; connect-src 'self' https://api.openai.com https://*.telemetrydeck.com https://nom.telemetrydeck.com local-file: file: data:; script-src 'self' 'unsafe-inline' blob:; media-src 'self' local-file: file: blob: data:; img-src 'self' local-file: file: blob: data:;"
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

// Function to migrate existing files from flat structure to new directory structure
async function migrateFilesToNewStructure() {
  try {
    // Check if migration is needed by looking for image files in the root directory
    const allFiles = await fs.readdir(appStorageDir);
    
    // Filter for image/video and JSON files directly in the root directory
    const mediaFiles = allFiles.filter(file => {
      const ext = path.extname(file).toLowerCase();
      return (ext === '.png' || ext === '.mp4') && !file.startsWith('.');
    });
    
    const jsonFiles = allFiles.filter(file => {
      return path.extname(file).toLowerCase() === '.json' && 
             file !== 'README.txt' && 
             !file.startsWith('.');
    });
    
    // If no files to migrate, return early
    if (mediaFiles.length === 0 && jsonFiles.length === 0) {
      console.log("No files to migrate, using new directory structure");
      return;
    }
    
    console.log(`Found ${mediaFiles.length} media files and ${jsonFiles.length} JSON files to migrate`);
    
    // Create a backup directory
    const backupDir = path.join(appStorageDir, '.backup-' + new Date().toISOString().replace(/:/g, '-'));
    await fs.ensureDir(backupDir);
    
    // Copy all files to backup first (safety measure)
    for (const file of [...mediaFiles, ...jsonFiles]) {
      const srcPath = path.join(appStorageDir, file);
      const destPath = path.join(backupDir, file);
      await fs.copy(srcPath, destPath);
    }
    
    console.log(`Backed up ${mediaFiles.length + jsonFiles.length} files to ${backupDir}`);
    
    // Now move files to their new locations
    const imagesDir = path.join(appStorageDir, 'images');
    const metadataDir = path.join(appStorageDir, 'metadata');
    
    // Move media files to images dir
    for (const file of mediaFiles) {
      const srcPath = path.join(appStorageDir, file);
      const destPath = path.join(imagesDir, file);
      await fs.move(srcPath, destPath, { overwrite: true });
    }
    
    // Move JSON files to metadata dir
    for (const file of jsonFiles) {
      const srcPath = path.join(appStorageDir, file);
      const destPath = path.join(metadataDir, file);
      await fs.move(srcPath, destPath, { overwrite: true });
    }
    
    // Handle trash directory if it exists in old format
    const oldTrashPath = path.join(appStorageDir, '.trash');
    if (await fs.pathExists(oldTrashPath)) {
      const trashFiles = await fs.readdir(oldTrashPath);
      
      // Filter and move trash files
      const trashMediaFiles = trashFiles.filter(file => {
        const ext = path.extname(file).toLowerCase();
        return (ext === '.png' || ext === '.mp4');
      });
      
      const trashJsonFiles = trashFiles.filter(file => {
        return path.extname(file).toLowerCase() === '.json';
      });
      
      // Move trash media files
      const trashImagesDir = path.join(trashDir, 'images');
      for (const file of trashMediaFiles) {
        const srcPath = path.join(oldTrashPath, file);
        const destPath = path.join(trashImagesDir, file);
        await fs.move(srcPath, destPath, { overwrite: true });
      }
      
      // Move trash JSON files
      const trashMetadataDir = path.join(trashDir, 'metadata');
      for (const file of trashJsonFiles) {
        const srcPath = path.join(oldTrashPath, file);
        const destPath = path.join(trashMetadataDir, file);
        await fs.move(srcPath, destPath, { overwrite: true });
      }
    }
    
    console.log("Migration to new directory structure completed successfully");
  } catch (error) {
    console.error("Error during file migration:", error);
  }
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
      // Return the file path
      return callback(decodeURI(url));
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

          // Construct the media object with correct paths
          const mediaObject = {
            ...metadata,
            id,
            url: localFileUrl,
            type: isVideo ? 'video' : metadata.type || 'image',
            actualFilePath: mediaPath,
            useDirectPath: true // Flag to indicate this is a direct file path
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
    return consent;
  } catch (error) {
    return false;
  }
});

ipcMain.handle('set-analytics-consent', async (event, consent) => {
  try {
    const result = analyticsPreferences.setConsent(consent);
    return result;
  } catch (error) {
    return false;
  }
}); 