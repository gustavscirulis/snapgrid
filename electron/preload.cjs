const { contextBridge, ipcRenderer } = require('electron');
const fs = require('fs');
const path = require('path');

contextBridge.exposeInMainWorld('electron', {
  openFile: () => ipcRenderer.invoke('dialog:openFile'),
  openFiles: () => ipcRenderer.invoke('dialog:openFiles'),
  openFolder: () => ipcRenderer.invoke('dialog:openFolder'),
  convertImageToBase64: async (fileUrl) => {
    try {
      let filePath = fileUrl;
      if (filePath.startsWith('local-file://')) {
        filePath = filePath.replace('local-file://', '');
      } else if (filePath.startsWith('file://')) {
        filePath = filePath.replace('file://', '');
      }

      const imageBuffer = await fs.promises.readFile(filePath);

      const ext = path.extname(filePath).toLowerCase();
      let mimeType = 'image/png'; 

      if (ext === '.jpg' || ext === '.jpeg') {
        mimeType = 'image/jpeg';
      } else if (ext === '.png') {
        mimeType = 'image/png';
      } else if (ext === '.gif') {
        mimeType = 'image/gif';
      } else if (ext === '.webp') {
        mimeType = 'image/webp';
      }

      const base64Data = `data:${mimeType};base64,${imageBuffer.toString('base64')}`;
      return base64Data;
    } catch (error) {
      console.error('Error converting image to base64:', error);
      throw error;
    }
  },
    checkFileAccess: (filePath) => ipcRenderer.invoke('check-file-access', filePath),
    minimize: () => ipcRenderer.send('window-minimize'),
    maximize: () => ipcRenderer.send('window-maximize'),
    close: () => ipcRenderer.send('window-close'),
    loadImages: () => ipcRenderer.invoke('load-images'),
    saveImage: (data) => ipcRenderer.invoke('save-image', data),
    saveUrlCard: (data) => ipcRenderer.invoke('save-url-card', data),
    deleteImage: (id) => ipcRenderer.invoke('delete-image', id),
    getAppStorageDir: () => ipcRenderer.invoke('get-app-storage-dir'),
    openStorageDir: () => ipcRenderer.invoke('open-storage-dir'),
    openUrl: (url) => ipcRenderer.invoke('open-url', url)
});