
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electron', {
  getAppStorageDir: () => ipcRenderer.invoke('get-app-storage-dir'),
  saveImage: (data) => ipcRenderer.invoke('save-image', data),
  loadImages: () => ipcRenderer.invoke('load-images'),
  deleteImage: (id) => ipcRenderer.invoke('delete-image', id),
  saveUrlCard: (data) => ipcRenderer.invoke('save-url-card', data),
});
