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

