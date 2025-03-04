
import { contextBridge, ipcRenderer } from 'electron';

contextBridge.exposeInMainWorld('electron', {
  loadImages: () => ipcRenderer.invoke('load-images'),
  saveImage: (data) => ipcRenderer.invoke('save-image', data),
  deleteImage: (id) => ipcRenderer.invoke('delete-image', id),
  saveUrlCard: (data) => ipcRenderer.invoke('save-url-card', data),
  getAppStorageDir: () => ipcRenderer.invoke('get-app-storage-dir')
});
