export function validateMediaFile(file: File): boolean {
  // Check if the file is an image
  if (file.type.startsWith('image/')) {
    return true;
  }

  // Check if the file is a browser-compatible video format
  const supportedVideoTypes = [
    'video/mp4',
    'video/webm',
    'video/ogg'
  ];

  return supportedVideoTypes.includes(file.type);
}

export function isVideoFile(file: File): boolean {
  return file.type.startsWith('video/');
}

export function validateImageFile(file: File): boolean {
  // Keep original function for backward compatibility
  // Check if the file is an image
  if (!file.type.startsWith('image/')) {
    return false;
  }

  // Check if the file size is less than 10MB
  const maxSize = 10 * 1024 * 1024; // 10MB
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
    };
    img.onerror = reject;
    img.src = URL.createObjectURL(file);
  });
}

export function calculateGridRowSpan(height: number, width: number, gridRowHeight = 10): number {
  // Calculate aspect ratio and determine how many grid rows the image should span
  const aspectRatio = height / width;
  const baseWidth = 300; // This should match the minmax value in CSS
  const imageHeight = baseWidth * aspectRatio;
  return Math.ceil(imageHeight / gridRowHeight) + 1; // +1 for some padding
}