const { contextBridge, ipcRenderer } = require('electron');
const fs = require('fs');
const path = require('path');

// Expose protected methods that allow the renderer process to use
// the ipcRenderer without exposing the entire object
contextBridge.exposeInMainWorld(
  'electron',
  {
    // Add API for checking file permissions
    checkFileAccess: (filePath) => ipcRenderer.invoke('check-file-access', filePath),
    // Window control methods
    minimize: () => ipcRenderer.send('window-minimize'),
    maximize: () => ipcRenderer.send('window-maximize'),
    close: () => ipcRenderer.send('window-close'),

    // File storage operations
    loadImages: () => ipcRenderer.invoke('load-images'),
    saveImage: (data) => ipcRenderer.invoke('save-image', data),
    updateMetadata: (data) => ipcRenderer.invoke('update-metadata', data),
    deleteImage: (id) => ipcRenderer.invoke('delete-image', id),
    restoreFromTrash: (id) => ipcRenderer.invoke('restore-from-trash', id),
    emptyTrash: () => ipcRenderer.invoke('empty-trash'),
    listTrash: () => ipcRenderer.invoke('list-trash'),
    getTrashDir: () => ipcRenderer.invoke('get-trash-dir'),

    // Storage path info
    getAppStorageDir: () => ipcRenderer.invoke('get-app-storage-dir'),
    openStorageDir: () => ipcRenderer.invoke('open-storage-dir'),

    // Browser functionality
    openUrl: (url) => ipcRenderer.invoke('open-url', url),

    // Secure API key management
    setApiKey: (service, key) => ipcRenderer.invoke('set-api-key', { service, key }),
    getApiKey: (service) => ipcRenderer.invoke('get-api-key', { service }),
    hasApiKey: (service) => ipcRenderer.invoke('has-api-key', { service }),
    deleteApiKey: (service) => ipcRenderer.invoke('delete-api-key', { service }),
    
    // Analytics settings
    getAnalyticsConsent: () => ipcRenderer.invoke('get-analytics-consent'),
    setAnalyticsConsent: (consent) => ipcRenderer.invoke('set-analytics-consent', consent),
    onAnalyticsConsentChanged: (callback) => {
      ipcRenderer.on('analytics-consent-changed', (_, consent) => callback(consent));
      return () => ipcRenderer.removeAllListeners('analytics-consent-changed');
    },

    // App information
    appVersion: require('../package.json').version,

    // Added methods
    convertImageToBase64: async (filePath) => {
      try {
        let fileUrl = filePath;
        if (fileUrl.startsWith('local-file://')) {
          fileUrl = fileUrl.replace('local-file://', '');
        } else if (fileUrl.startsWith('file://')) {
          fileUrl = fileUrl.replace('file://', '');
        }

        const imageBuffer = await new Promise((resolve, reject) => {
          fs.readFile(fileUrl, (err, data) => {
            if (err) reject(err);
            else resolve(data);
          });
        });

        const ext = path.extname(fileUrl).toLowerCase();
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
    
    // Menu events - add event listeners for menu-triggered events
    onImportFiles: (callback) => {
      ipcRenderer.on('import-files', (_, filePaths) => callback(filePaths));
      return () => ipcRenderer.removeAllListeners('import-files');
    },
    
    onOpenStorageLocation: (callback) => {
      ipcRenderer.on('open-storage-location', () => callback());
      return () => ipcRenderer.removeAllListeners('open-storage-location');
    },
    
    onOpenSettings: (callback) => {
      ipcRenderer.on('open-settings', () => callback());
      return () => ipcRenderer.removeAllListeners('open-settings');
    }
  }
);