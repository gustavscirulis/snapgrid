
import { app, BrowserWindow, ipcMain, dialog, shell } from 'electron';
import path from 'path';
import { fileURLToPath } from 'url';
import fs from 'fs-extra';
import os from 'os';

// Get the directory name of the current module
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Detect development mode without using electron-is-dev
const isDev = process.env.NODE_ENV === 'development' || !/[\\/]app\.asar[\\/]/.test(__dirname);

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
    console.log('Using Documents folder path:', storageDir);
    
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
    console.log('Using userData path:', storageDir);
  }
  
  // Ensure directory exists
  fs.ensureDirSync(storageDir);
  
  return storageDir;
};

function createWindow() {
  appStorageDir = getAppStorageDir();
  console.log('App storage directory:', appStorageDir);
  
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
    },
  });

  // In production, use file protocol with the correct path
  // In development, use localhost server
  const startUrl = isDev 
    ? 'http://localhost:8080' 
    : `file://${path.join(__dirname, '../dist/index.html')}`;
    
  console.log('Loading application from:', startUrl);
  
  mainWindow.loadURL(startUrl);

  if (isDev) {
    mainWindow.webContents.openDevTools({ mode: 'detach' });
  }

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

app.whenReady().then(createWindow);

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

ipcMain.handle('save-image', async (event, { id, file, metadata }) => {
  try {
    // Save image file
    const imagePath = path.join(appStorageDir, `${id}.png`);
    await fs.writeFile(imagePath, file);
    
    // Save metadata as separate JSON file
    const metadataPath = path.join(appStorageDir, `${id}.json`);
    await fs.writeJson(metadataPath, {
      ...metadata,
      filePath: imagePath // Include actual file path in metadata
    });
    
    console.log(`Image saved to: ${imagePath}`);
    return { success: true, path: imagePath };
  } catch (error) {
    console.error('Error saving image:', error);
    return { success: false, error: error.message };
  }
});

ipcMain.handle('load-images', async () => {
  try {
    const files = await fs.readdir(appStorageDir);
    const jsonFiles = files.filter(file => file.endsWith('.json'));
    
    const images = await Promise.all(
      jsonFiles.map(async (file) => {
        const id = path.basename(file, '.json');
        const metadataPath = path.join(appStorageDir, file);
        const imagePath = path.join(appStorageDir, `${id}.png`);
        
        try {
          // Check if both metadata and image exist
          if (!(await fs.pathExists(imagePath))) {
            console.warn(`Image file not found: ${imagePath}`);
            return null;
          }
          
          // Load metadata
          const metadata = await fs.readJson(metadataPath);
          
          return {
            ...metadata,
            id,
            url: `file://${imagePath}`,
            filePath: imagePath
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

ipcMain.handle('delete-image', async (event, id) => {
  try {
    const imagePath = path.join(appStorageDir, `${id}.png`);
    const metadataPath = path.join(appStorageDir, `${id}.json`);
    
    await fs.remove(imagePath);
    await fs.remove(metadataPath);
    
    console.log(`Deleted image: ${imagePath}`);
    return { success: true };
  } catch (error) {
    console.error('Error deleting image:', error);
    return { success: false, error: error.message };
  }
});

ipcMain.handle('save-url-card', async (event, { id, metadata }) => {
  try {
    const metadataPath = path.join(appStorageDir, `${id}.json`);
    await fs.writeJson(metadataPath, metadata);
    console.log(`Saved URL card: ${metadataPath}`);
    return { success: true };
  } catch (error) {
    console.error('Error saving URL card:', error);
    return { success: false, error: error.message };
  }
});

ipcMain.handle('save-video', async (event, { id, file, metadata }) => {
  try {
    // Save video file
    const videoPath = path.join(appStorageDir, `${id}.mp4`);
    await fs.writeFile(videoPath, file);
    
    // Save metadata as separate JSON file
    const metadataPath = path.join(appStorageDir, `${id}.json`);
    await fs.writeJson(metadataPath, {
      ...metadata,
      filePath: videoPath // Include actual file path in metadata
    });
    
    console.log(`Video saved to: ${videoPath}`);
    return { success: true, path: videoPath };
  } catch (error) {
    console.error('Error saving video:', error);
    return { success: false, error: error.message };
  }
});
