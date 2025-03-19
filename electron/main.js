import { app, BrowserWindow, ipcMain, dialog, shell, protocol } from 'electron';
import path from 'path';
import { fileURLToPath } from 'url';
import fs from 'fs-extra';
import os from 'os';
import {promises as fsPromises} from 'fs'; // Import fsPromises


// Get the directory name of the current module
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Detect development mode without using electron-is-dev
const isDev = process.env.NODE_ENV === 'development' || !/[\\/]app\.asar[\\/]/.test(__dirname);

// Helper function for conditional logging
const devLog = (...args) => {
  if (isDev) {
    console.log(...args);
  }
};

// Helper function for conditional warning logging
const devWarn = (...args) => {
  if (isDev) {
    console.warn(...args);
  }
};

// Global storage path that will be exposed to the renderer
let appStorageDir;
let mainWindow;

// Determine app storage directory in iCloud or local folder
const getAppStorageDir = () => {
  const platform = process.platform;
  let storageDir;

  if (platform === 'darwin') {
    // On macOS, try to use Documents folder first for visibility
    const homeDir = os.homedir();
    storageDir = path.join(homeDir, 'Documents', 'UIReferenceApp');
    devLog('Using Documents folder path:', storageDir);

    // Create a README file to help users find the folder
    const readmePath = path.join(storageDir, 'README.txt');
    if (!fs.existsSync(readmePath)) {
      fs.ensureDirSync(storageDir);
      fs.writeFileSync(
        readmePath, 
        'This folder contains your UI Reference app images and data.\n' +
        'Files are stored as PNG images with accompanying JSON metadata.\n\n' +
        'Storage location: ' + storageDir
      );
    }
  } else {
    // For other platforms, use app.getPath('userData')
    storageDir = path.join(app.getPath('userData'), 'images');
    devLog('Using userData path:', storageDir);
  }

  // Ensure directory exists
  fs.ensureDirSync(storageDir);

  return storageDir;
};

function createWindow() {
  appStorageDir = getAppStorageDir();
  devLog('App storage directory:', appStorageDir);

  mainWindow = new BrowserWindow({
    width: 1200,
    height: 800,
    frame: false, // Hides the default title bar
    titleBarStyle: "hidden", // Hides default macOS traffic light buttons
    titleBarOverlay: false, // Ensure no default overlay
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      preload: path.join(__dirname, 'preload.cjs'),
      webSecurity: true, // Added for security
      sandbox: false // Added to allow Node.js modules in preload
    },
  });

  // In production, use file protocol with the correct path
  // In development, use localhost server
  const startUrl = isDev 
    ? 'http://localhost:8080' 
    : `file://${path.join(__dirname, '../dist/index.html')}`;

  devLog('Loading application from:', startUrl);

  // Add webSecurity configuration and CSP for local media playback and OpenAI API
  mainWindow.webContents.session.webRequest.onHeadersReceived((details, callback) => {
    callback({
      responseHeaders: {
        ...details.responseHeaders,
        'Content-Security-Policy': [
          "default-src 'self' 'unsafe-inline' local-file: file: data:; " +
          "connect-src 'self' https://api.openai.com https://api.allorigins.win https://* local-file: file: data:; " +
          "img-src 'self' https://* local-file: file: blob: data:; " +
          "script-src 'self' 'unsafe-inline' blob:; " +
          "media-src 'self' local-file: file: blob: data:;"
        ]
      }
    });
  });

  mainWindow.loadURL(startUrl);

  if (isDev) {
    mainWindow.webContents.openDevTools({ mode: 'detach' });
    
    // Suppress DevTools console errors related to Autofill and other missing features
    mainWindow.webContents.on('did-finish-load', () => {
      mainWindow.webContents.executeJavaScript(`
        // Suppress specific console errors
        const originalConsoleError = console.error;
        console.error = function(...args) {
          // Filter out DevTools protocol errors
          if (args.length > 0 && typeof args[0] === 'string' && 
              (args[0].includes("Request Autofill") || 
               args[0].includes("wasn't found"))) {
            return;
          }
          originalConsoleError.apply(console, args);
        };
      `);
    });
  }

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
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

  createWindow();
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

app.on('activate', () => {
  if (mainWindow === null) {
    createWindow();
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

// IPC handlers for file system operations
ipcMain.handle('get-app-storage-dir', () => {
  return appStorageDir;
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

    // Strip data URL prefix to get base64 data
    let base64Data;
    if (isVideo) {
      base64Data = dataUrl.replace(/^data:video\/\w+;base64,/, '');
    } else {
      base64Data = dataUrl.replace(/^data:image\/\w+;base64,/, '');
    }
    const buffer = Buffer.from(base64Data, 'base64');

    // Save media file with correct extension
    const filePath = path.join(appStorageDir, `${id}${fileExt}`);
    await fs.writeFile(filePath, buffer);

    // Ensure metadata is serializable
    const safeMetadata = safeSerialize({
      ...metadata,
      filePath: filePath, // Include actual file path in metadata
      type: isVideo ? 'video' : 'image' // Ensure type is correctly set
    });

    // Save metadata as separate JSON file
    const metadataPath = path.join(appStorageDir, `${id}.json`);
    await fs.writeJson(metadataPath, safeMetadata);

    return { success: true, path: filePath };
  } catch (error) {
    console.error('Error saving media:', error);
    return { success: false, error: error.message };
  }
});

// Add a helper function for safer object serialization
const safeSerialize = (obj) => {
  try {
    // Test if the object can be serialized
    JSON.stringify(obj);
    return obj;
  } catch (error) {
    // If serialization fails, return a simplified error object
    return {
      error: 'Object could not be serialized',
      message: error.message
    };
  }
};

ipcMain.handle('load-images', async () => {
  try {
    const files = await fs.readdir(appStorageDir);
    const jsonFiles = files.filter(file => file.endsWith('.json'));

    const images = await Promise.all(
      jsonFiles.map(async (file) => {
        const id = path.basename(file, '.json');
        const metadataPath = path.join(appStorageDir, file);

        // Check if this is a video based on id prefix
        const isVideo = id.startsWith('vid_');
        // Use appropriate extension
        const fileExt = isVideo ? '.mp4' : '.png';
        const mediaPath = path.join(appStorageDir, `${id}${fileExt}`);

        try {
          // Check if both metadata and media file exist
          if (!(await fs.pathExists(mediaPath))) {
            // Only log in development mode
            devWarn(`Media file not found: ${mediaPath}`);
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

          return safeSerialize(mediaObject);
        } catch (err) {
          // Only log in development mode
          devWarn(`Error loading image ${id}:`, err);
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

ipcMain.handle('delete-image', async (event, id) => {
  try {
    // Determine if this is a video based on id prefix
    const isVideo = id.startsWith('vid_');
    const fileExt = isVideo ? '.mp4' : '.png';

    const mediaPath = path.join(appStorageDir, `${id}${fileExt}`);
    const metadataPath = path.join(appStorageDir, `${id}.json`);

    await fs.remove(mediaPath);
    await fs.remove(metadataPath);

    return { success: true };
  } catch (error) {
    console.error('Error deleting image:', error);
    return { success: false, error: error.message };
  }
});

ipcMain.handle('save-url-card', async (event, { id, metadata }) => {
  try {
    // Ensure metadata is serializable before saving
    let safeMetadata;
    try {
      // Test serialization
      JSON.stringify(metadata);
      safeMetadata = metadata;
    } catch (err) {
      devWarn('Metadata contains non-serializable data, cleaning...', err);
      // Create a clean version with only serializable properties
      safeMetadata = {
        id: metadata.id,
        type: metadata.type,
        url: metadata.url,
        width: metadata.width || 400,
        height: metadata.height || 400,
        createdAt: metadata.createdAt || new Date(),
        title: metadata.title || '',
        description: metadata.description || ''
      };
      
      // Selectively add other properties if they exist and are serializable
      if (metadata.thumbnailUrl) safeMetadata.thumbnailUrl = metadata.thumbnailUrl;
      if (metadata.faviconUrl) safeMetadata.faviconUrl = metadata.faviconUrl;
    }
    
    const metadataPath = path.join(appStorageDir, `${id}.json`);
    await fs.writeJson(metadataPath, safeMetadata);
    devLog(`Saved URL card: ${metadataPath}`);
    return { success: true };
  } catch (error) {
    console.error('Error saving URL card:', error);
    return { success: false, error: error.message };
  }
});

// Add handler for checking file access permissions
ipcMain.handle('check-file-access', async (event, filePath) => {
  try {
    // Check if file exists and is readable
    await fsPromises.access(filePath, fsPromises.constants.R_OK); // Use fsPromises here
    devLog(`File is accessible: ${filePath}`);
    return { success: true, accessible: true };
  } catch (error) {
    devWarn(`File access error for ${filePath}:`, error);
    return { success: true, accessible: false, error: error.message };
  }
});

ipcMain.handle('update-metadata', async (event, { id, metadata }) => {
  try {
    // Ensure metadata is serializable
    const safeMetadata = safeSerialize(metadata);
    
    const metadataPath = path.join(appStorageDir, `${id}.json`);
    await fs.writeJson(metadataPath, safeMetadata);
    devLog(`Updated metadata at: ${metadataPath}`);
    return { success: true };
  } catch (error) {
    console.error('Error updating metadata:', error);
    return { success: false, error: error.message };
  }
});

ipcMain.handle('open-url', async (event, url) => {
  try {
    devLog(`Opening URL in default browser: ${url}`);
    await shell.openExternal(url);
    return { success: true };
  } catch (error) {
    console.error('Error opening URL:', error);
    return { success: false, error: error.message };
  }
});