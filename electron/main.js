
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

let mainWindow;

function createWindow() {
  appStorageDir = getAppStorageDir();
  console.log('App storage directory:', appStorageDir);
  
  mainWindow = new BrowserWindow({
    width: 1200,
    height: 800,
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

// IPC handlers for file system operations
ipcMain.handle('get-app-storage-dir', () => {
  return appStorageDir;
});

ipcMain.handle('open-storage-dir', () => {
  return shell.openPath(appStorageDir);
});

ipcMain.handle('save-image', async (event, { id, dataUrl, metadata }) => {
  try {
    // Create image file path
    const imagePath = path.join(appStorageDir, `${id}.png`);
    
    // If dataUrl is provided, save the image
    if (dataUrl) {
      // Strip data URL prefix to get base64 data
      const base64Data = dataUrl.replace(/^data:image\/\w+;base64,/, '');
      const buffer = Buffer.from(base64Data, 'base64');
      
      // Save image file
      await fs.writeFile(imagePath, buffer);
      console.log(`Image file saved to: ${imagePath}`);
    }
    
    // Save metadata as separate JSON file
    const metadataPath = path.join(appStorageDir, `${id}.json`);
    await fs.writeJson(metadataPath, {
      ...metadata,
      actualFilePath: imagePath // Include actual file path in metadata
    });
    
    console.log(`Metadata saved to: ${metadataPath}`);
    return { success: true, path: imagePath };
  } catch (error) {
    console.error('Error saving image:', error);
    return { success: false, error: error.message };
  }
});

ipcMain.handle('load-images', async () => {
  try {
    console.log("Loading images from:", appStorageDir);
    const files = await fs.readdir(appStorageDir);
    const jsonFiles = files.filter(file => file.endsWith('.json'));
    
    console.log(`Found ${jsonFiles.length} JSON files`);
    
    const images = await Promise.all(
      jsonFiles.map(async (file) => {
        const id = path.basename(file, '.json');
        const metadataPath = path.join(appStorageDir, file);
        const imagePath = path.join(appStorageDir, `${id}.png`);
        
        try {
          // Check if both metadata and image exist
          if (!(await fs.pathExists(imagePath)) && !(metadata?.type === "url")) {
            console.warn(`Image file not found: ${imagePath}`);
            return null;
          }
          
          // Load metadata
          const metadata = await fs.readJson(metadataPath);
          
          // For URL cards, just return the metadata
          if (metadata.type === "url") {
            return {
              ...metadata,
              id
            };
          }
          
          // For images/videos, return with the actual file path
          return {
            ...metadata,
            id,
            actualFilePath: imagePath,
            // Use the actual file path for rendering
            url: imagePath
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
    
    // Delete the image file if it exists
    if (await fs.pathExists(imagePath)) {
      await fs.remove(imagePath);
    }
    
    // Delete the metadata file
    if (await fs.pathExists(metadataPath)) {
      await fs.remove(metadataPath);
    }
    
    console.log(`Deleted image: ${id}`);
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
