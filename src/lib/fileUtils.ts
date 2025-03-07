
/**
 * Formats a file path to ensure it has the correct file:// protocol prefix
 * for use in src attributes in the application
 */
export function formatFilePath(path: string): string {
  if (!path) return '';
  
  // If already has file:// protocol, return as is
  if (path.startsWith('file://')) {
    return path;
  }
  
  // Add file:// protocol
  return `file://${path}`;
}

/**
 * Checks if the application is running in Electron
 */
export function isElectronEnvironment(): boolean {
  return window && typeof window.electron !== 'undefined' && window.electron !== null;
}
