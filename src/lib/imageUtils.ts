
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
  
  // Check file size (max 100MB)
  const maxSize = 100 * 1024 * 1024; // 100MB
  if (file.size > maxSize) {
    return false;
  }
  
  return true;
}

export function getImageDimensions(file: File): Promise<{ width: number; height: number }> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => {
      resolve({
        width: img.width,
        height: img.height,
      });
      // Clean up object URL to prevent memory leaks
      URL.revokeObjectURL(img.src);
    };
    img.onerror = reject;
    img.src = URL.createObjectURL(file);
  });
}

export function getVideoDimensions(file: File): Promise<{ width: number; height: number; duration: number }> {
  return new Promise((resolve, reject) => {
    const video = document.createElement('video');
    video.preload = 'metadata';
    video.onloadedmetadata = () => {
      resolve({
        width: video.videoWidth,
        height: video.videoHeight,
        duration: video.duration
      });
      // Clean up object URL to prevent memory leaks
      URL.revokeObjectURL(video.src);
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

export function formatDuration(seconds: number): string {
  const minutes = Math.floor(seconds / 60);
  const remainingSeconds = Math.floor(seconds % 60);
  return `${minutes}:${remainingSeconds.toString().padStart(2, '0')}`;
}
