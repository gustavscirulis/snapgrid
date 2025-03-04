
import { app, BrowserWindow, ipcMain, dialog } from 'electron';
import path from 'path';
import { fileURLToPath } from 'url';
import fs from 'fs-extra';
import isDev from 'electron-is-dev';
import os from 'os';

// Get the directory name of the current module
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Determine app storage directory in iCloud or local folder
const getAppStorageDir = () => {
  const platform = process.platform;
  let appStorageDir;
  
  if (platform === 'darwin') {
    // On macOS, try to use iCloud Drive if available
    const homeDir = os.homedir();
    const iCloudDrive = path.join(homeDir, 'Library', 'Mobile Documents', 'com~apple~CloudDocs');
    
    if (fs.existsSync(iCloudDrive)) {
      appStorageDir = path.join(iCloudDrive, 'UIReferenceApp');
    } else {
      // Fallback to Documents folder
      appStorageDir = path.join(homeDir, 'Documents', 'UIReferenceApp');
    }
  } else {
    // For other platforms, use app.getPath('userData')
    appStorageDir = path.join(app.getPath('userData'), 'images');
  }
  
  // Ensure directory exists
  fs.ensureDirSync(appStorageDir);
  
  return appStorageDir;
};

let mainWindow;
let appStorageDir;

function createWindow() {
  appStorageDir = getAppStorageDir();
  console.log('App storage directory:', appStorageDir);
  
  mainWindow = new BrowserWindow({
    width: 1200,
    height: 800,
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false,
      preload: path.join(__dirname, 'preload.js'),
    },
  });

  const startUrl = isDev 
    ? 'http://localhost:8080' 
    : `file://${path.join(__dirname, '../dist/index.html')}`;
    
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

ipcMain.handle('save-image', async (event, { id, dataUrl, metadata }) => {
  try {
    const base64Data = dataUrl.replace(/^data:image\/\w+;base64,/, '');
    const buffer = Buffer.from(base64Data, 'base64');
    const imagePath = path.join(appStorageDir, `${id}.png`);
    const metadataPath = path.join(appStorageDir, `${id}.json`);
    
    await fs.writeFile(imagePath, buffer);
    await fs.writeJson(metadataPath, metadata);
    
    return { success: true, path: imagePath };
  } catch (error) {
    console.error('Error saving image:', error);
    return { success: false, error: error.message };
  }
});

ipcMain.handle('load-images', async () => {
  try {
    const files = await fs.readdir(appStorageDir);
    const imageFiles = files.filter(file => file.endsWith('.json'));
    
    const images = await Promise.all(
      imageFiles.map(async (file) => {
        const id = path.basename(file, '.json');
        const metadataPath = path.join(appStorageDir, file);
        const imagePath = path.join(appStorageDir, `${id}.png`);
        
        try {
          // Check if both metadata and image exist
          if (!(await fs.pathExists(imagePath))) {
            return null;
          }
          
          const metadata = await fs.readJson(metadataPath);
          const imageData = await fs.readFile(imagePath);
          const base64Image = `data:image/png;base64,${imageData.toString('base64')}`;
          
          return {
            ...metadata,
            id,
            url: base64Image
          };
        } catch (err) {
          console.error(`Error loading image ${id}:`, err);
          return null;
        }
      })
    );
    
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
    return { success: true };
  } catch (error) {
    console.error('Error saving URL card:', error);
    return { success: false, error: error.message };
  }
});
