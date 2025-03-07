
export function validateImageFile(file: File): boolean {
  // Check if the file is an image or video
  if (!file.type.match('image.*') && !file.type.match('video.*')) {
    return false;
  }
  
  // Check file size (max 50MB)
  const maxSize = 50 * 1024 * 1024; // 50MB
  if (file.size > maxSize) {
    return false;
  }
  
  return true;
}

export function getImageDimensions(file: File): Promise<{ width: number; height: number }> {
  return new Promise((resolve, reject) => {
    if (file.type.startsWith('video/')) {
      const video = document.createElement('video');
      video.preload = 'metadata';
      
      video.onloadedmetadata = () => {
        resolve({
          width: video.videoWidth || 640, // Fallback width if metadata can't be read
          height: video.videoHeight || 360, // Fallback height if metadata can't be read
        });
      };
      
      video.onerror = reject;
      video.src = URL.createObjectURL(file);
    } else {
      // Original image handling
      const img = new Image();
      img.onload = () => {
        resolve({
          width: img.width,
          height: img.height,
        });
      };
      img.onerror = reject;
      img.src = URL.createObjectURL(file);
    }
  });
}

export function calculateGridRowSpan(height: number, width: number, gridRowHeight = 10): number {
  // Calculate aspect ratio and determine how many grid rows the image should span
  const aspectRatio = height / width;
  const baseWidth = 300; // This should match the minmax value in CSS
  const imageHeight = baseWidth * aspectRatio;
  return Math.ceil(imageHeight / gridRowHeight) + 1; // +1 for some padding
}

export function getFileExtension(file: File): string {
  // Get file extension from MIME type if available
  if (file.type) {
    const mimeTypeParts = file.type.split('/');
    if (mimeTypeParts.length === 2) {
      return mimeTypeParts[1].split(';')[0]; // Handle cases like "video/mp4;codecs=..."
    }
  }
  
  // Fallback to filename extension
  const filename = file.name || '';
  const parts = filename.split('.');
  if (parts.length > 1) {
    return parts[parts.length - 1].toLowerCase();
  }
  
  // Default fallback
  return file.type.startsWith('video/') ? 'mp4' : 'jpg';
}

export function isVideoFile(file: File): boolean {
  return file.type.startsWith('video/');
}

