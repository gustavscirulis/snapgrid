export function validateImageFile(file: File): boolean {
  // Check if the file is an image
  if (!file.type.match('image.*')) {
    return false;
  }
  
  // Check file size (max 10MB)
  const maxSize = 10 * 1024 * 1024; // 10MB
  if (file.size > maxSize) {
    return false;
  }
  
  return true;
}

export function validateVideoFile(file: File): boolean {
  // Check if the file is a video
  if (!file.type.match('video.*')) {
    return false;
  }
  
  // Check file size (max 50MB)
  const maxSize = 50 * 1024 * 1024; // 50MB
  if (file.size > maxSize) {
    return false;
  }
  
  return true;
}

export function validateMediaFile(file: File): { valid: boolean; type: 'image' | 'video' | null } {
  if (validateImageFile(file)) {
    return { valid: true, type: 'image' };
  }
  
  if (validateVideoFile(file)) {
    return { valid: true, type: 'video' };
  }
  
  return { valid: false, type: null };
}

export function getImageDimensions(file: File): Promise<{ width: number; height: number }> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => {
      resolve({
        width: img.width,
        height: img.height,
      });
    };
    img.onerror = reject;
    img.src = URL.createObjectURL(file);
  });
}

export function getVideoDimensions(file: File): Promise<{ width: number; height: number }> {
  return new Promise((resolve, reject) => {
    const video = document.createElement('video');
    video.preload = 'metadata';
    
    video.onloadedmetadata = () => {
      resolve({
        width: video.videoWidth,
        height: video.videoHeight,
      });
    };
    
    video.onerror = reject;
    video.src = URL.createObjectURL(file);
  });
}

export function calculateGridRowSpan(height: number, width: number, gridRowHeight = 10): number {
  // Calculate aspect ratio and determine how many grid rows the image should span
  const aspectRatio = height / width;
  const baseWidth = 300; // This should match the minmax value in CSS
  const imageHeight = baseWidth * aspectRatio;
  return Math.ceil(imageHeight / gridRowHeight) + 1; // +1 for some padding
}

export function generateVideoThumbnail(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const video = document.createElement('video');
    video.preload = 'metadata';
    video.muted = true;
    video.playsInline = true;
    
    video.onloadeddata = () => {
      // Seek to 1 second or 25% of the video, whichever is less
      const seekTime = Math.min(1, video.duration * 0.25);
      video.currentTime = seekTime;
    };
    
    video.onseeked = () => {
      const canvas = document.createElement('canvas');
      canvas.width = video.videoWidth;
      canvas.height = video.videoHeight;
      
      const ctx = canvas.getContext('2d');
      if (!ctx) {
        reject(new Error('Could not get 2D context'));
        return;
      }
      
      ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
      
      try {
        const thumbnailUrl = canvas.toDataURL('image/jpeg', 0.7);
        resolve(thumbnailUrl);
      } catch (e) {
        reject(e);
      } finally {
        URL.revokeObjectURL(video.src);
      }
    };
    
    video.onerror = () => {
      reject(new Error('Error generating video thumbnail'));
      URL.revokeObjectURL(video.src);
    };
    
    video.src = URL.createObjectURL(file);
  });
}

// New helper function to get the appropriate media source URL
export function getMediaSourceUrl(item: { url: string; actualFilePath?: string; type: string; fileExtension?: string }): string {
  const isElectron = Boolean(window?.electron);
  
  if (isElectron && item.actualFilePath) {
    // Use the actual file path in Electron mode
    return `file://${item.actualFilePath}`;
  }
  
  // Fall back to the data URL for browser mode or if file path is unavailable
  return item.url;
}

// Get file extension from mime type
export function getFileExtensionFromMimeType(mimeType: string): string {
  const mimeToExt: Record<string, string> = {
    // Image types
    'image/jpeg': 'jpg',
    'image/jpg': 'jpg',
    'image/png': 'png',
    'image/gif': 'gif',
    'image/webp': 'webp',
    'image/svg+xml': 'svg',
    'image/bmp': 'bmp',
    'image/tiff': 'tiff',
    
    // Video types
    'video/mp4': 'mp4',
    'video/webm': 'webm',
    'video/ogg': 'ogv',
    'video/quicktime': 'mov',
    'video/x-msvideo': 'avi',
    'video/x-matroska': 'mkv',
    'video/mpeg': 'mpg'
  };
  
  return mimeToExt[mimeType] || 'bin'; // Default to binary if unknown
}

// Extract mime type from a data URL
export function getMimeTypeFromDataUrl(dataUrl: string): string {
  const match = dataUrl.match(/^data:([^;]+);base64,/);
  return match ? match[1] : 'application/octet-stream';
}
