
import { contextBridge, ipcRenderer } from 'electron';

// Expose protected methods that allow the renderer process to use
// the ipcRenderer without exposing the entire object
contextBridge.exposeInMainWorld(
  'electron',
  {
    // File storage operations
    loadImages: () => ipcRenderer.invoke('load-images'),
    saveImage: (data) => ipcRenderer.invoke('save-image', data),
    saveUrlCard: (data) => ipcRenderer.invoke('save-url-card', data),
    deleteImage: (id) => ipcRenderer.invoke('delete-image', id),
    
    // Storage path info
    getAppStorageDir: () => ipcRenderer.invoke('get-app-storage-dir'),
    openStorageDir: () => ipcRenderer.invoke('open-storage-dir')
  }
);
