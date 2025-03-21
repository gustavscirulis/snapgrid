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
    saveUrlCard: (data) => ipcRenderer.invoke('save-url-card', data),
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

    convertImageToBase64: async (fileUrl) => {
      try {
        let filePath = fileUrl;
        if (filePath.startsWith('local-file://')) {
          filePath = filePath.replace('local-file://', '');
        } else if (filePath.startsWith('file://')) {
          filePath = filePath.replace('file://', '');
        }

        const imageBuffer = await new Promise((resolve, reject) => {
          fs.readFile(filePath, (err, data) => {
            if (err) reject(err);
            else resolve(data);
          });
        });

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

    // Proxy function to make OpenAI API requests from main process
    callOpenAI: async (apiKey, payload) => {
      try {
        // This function runs in the Node.js context and can make network requests
        const https = require('https');

        return new Promise((resolve, reject) => {
          const options = {
            hostname: 'api.openai.com',
            port: 443,
            path: '/v1/chat/completions',
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${apiKey}`
            }
          };

          const req = https.request(options, (res) => {
            let data = '';

            res.on('data', (chunk) => {
              data += chunk;
            });

            res.on('end', () => {
              if (res.statusCode >= 200 && res.statusCode < 300) {
                resolve(JSON.parse(data));
              } else {
                reject(new Error(`API request failed with status ${res.statusCode}: ${data}`));
              }
            });
          });

          req.on('error', (error) => {
            reject(error);
          });

          req.write(JSON.stringify(payload));
          req.end();
        });
      } catch (error) {
        console.error('Error calling OpenAI API:', error);
        throw error;
      }
    },
  }
);