// Add the missing load-images handler
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
            console.warn(`Media file not found: ${mediaPath}`);
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

          return mediaObject;
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

// Add the delete-image handler
ipcMain.handle('delete-image', async (event, id) => {
  try {
    // Determine if this is a video based on id prefix
    const isVideo = id.startsWith('vid_');
    const fileExt = isVideo ? '.mp4' : '.png';

    const mediaPath = path.join(appStorageDir, `${id}${fileExt}`);
    const metadataPath = path.join(appStorageDir, `${id}.json`);
    const trashMediaPath = path.join(trashDir, `${id}${fileExt}`);
    const trashMetadataPath = path.join(trashDir, `${id}.json`);

    // Move files to trash instead of deleting
    await fs.move(mediaPath, trashMediaPath, { overwrite: true });
    await fs.move(metadataPath, trashMetadataPath, { overwrite: true });

    console.log(`Moved media to trash: ${trashMediaPath}`);
    return { success: true };
  } catch (error) {
    console.error('Error moving image to trash:', error);
    return { success: false, error: error.message };
  }
});

// Add restore-from-trash handler
ipcMain.handle('restore-from-trash', async (event, id) => {
  try {
    // Determine if this is a video based on id prefix
    const isVideo = id.startsWith('vid_');
    const fileExt = isVideo ? '.mp4' : '.png';

    const mediaPath = path.join(appStorageDir, `${id}${fileExt}`);
    const metadataPath = path.join(appStorageDir, `${id}.json`);
    const trashMediaPath = path.join(trashDir, `${id}${fileExt}`);
    const trashMetadataPath = path.join(trashDir, `${id}.json`);

    // Move files back from trash
    await fs.move(trashMediaPath, mediaPath, { overwrite: true });
    await fs.move(trashMetadataPath, metadataPath, { overwrite: true });

    console.log(`Restored media from trash: ${mediaPath}`);
    return { success: true };
  } catch (error) {
    console.error('Error restoring from trash:', error);
    return { success: false, error: error.message };
  }
});

// Add empty-trash handler
ipcMain.handle('empty-trash', async () => {
  try {
    await fs.emptyDir(trashDir);
    console.log('Trash emptied successfully');
    return { success: true };
  } catch (error) {
    console.error('Error emptying trash:', error);
    return { success: false, error: error.message };
  }
});

// Add list-trash handler
ipcMain.handle('list-trash', async () => {
  try {
    const files = await fs.readdir(trashDir);
    const jsonFiles = files.filter(file => file.endsWith('.json'));

    const trashItems = await Promise.all(
      jsonFiles.map(async (file) => {
        const id = path.basename(file, '.json');
        const metadataPath = path.join(trashDir, file);
        const isVideo = id.startsWith('vid_');
        const fileExt = isVideo ? '.mp4' : '.png';
        const mediaPath = path.join(trashDir, `${id}${fileExt}`);

        try {
          if (!(await fs.pathExists(mediaPath))) {
            console.warn(`Trash media file not found: ${mediaPath}`);
            return null;
          }

          const metadata = await fs.readJson(metadataPath);
          const localFileUrl = `local-file://${mediaPath}`;

          return {
            ...metadata,
            id,
            url: localFileUrl,
            type: isVideo ? 'video' : metadata.type || 'image',
            actualFilePath: mediaPath,
            useDirectPath: true
          };
        } catch (err) {
          console.error(`Error loading trash item ${id}:`, err);
          return null;
        }
      })
    );

    return trashItems.filter(Boolean);
  } catch (error) {
    console.error('Error listing trash:', error);
    return [];
  }
});

// Add check-file-access handler
ipcMain.handle('check-file-access', async (event, filePath) => {
  try {
    // Check if file exists and is readable
    await fsPromises.access(filePath, fsPromises.constants.R_OK);
    console.log(`File is accessible: ${filePath}`);
    return { success: true, accessible: true };
  } catch (error) {
    console.error(`File access error for ${filePath}:`, error);
    return { success: true, accessible: false, error: error.message };
  }
});

// Add update-metadata handler
ipcMain.handle('update-metadata', async (event, { id, metadata }) => {
  try {
    const metadataPath = path.join(appStorageDir, `${id}.json`);
    await fs.writeJson(metadataPath, metadata);
    console.log(`Updated metadata at: ${metadataPath}`);
    return { success: true };
  } catch (error) {
    console.error('Error updating metadata:', error);
    return { success: false, error: error.message };
  }
}); 