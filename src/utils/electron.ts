
/**
 * Utility functions for Electron-related operations
 */

/**
 * Check if the app is running in Electron environment
 */
export const isElectron = (): boolean => {
  try {
    // More robust check for Electron environment
    return (
      typeof window !== 'undefined' && 
      typeof window.electron !== 'undefined' && 
      window.electron !== null && 
      Object.keys(window.electron).length > 0
    );
  } catch (error) {
    console.error('Error checking Electron environment:', error);
    return false;
  }
};

/**
 * Get the file protocol for local files
 * Returns the appropriate protocol based on the environment
 */
export const getLocalFileUrl = (filePath: string): string => {
  // In Electron, the main process registers a custom protocol handler
  return `local-file://${filePath}`;
};

/**
 * Check if a file path is accessible
 * Note: This is a stub implementation since window.electron.checkFileAccess doesn't exist yet
 */
export const checkFileAccess = async (filePath: string): Promise<boolean> => {
  if (!isElectron()) {
    console.warn('File access check not available in browser mode');
    return false;
  }
  
  try {
    // Check if the API exists before calling it
    if (window.electron && 'checkFileAccess' in window.electron) {
      const result = await window.electron.checkFileAccess(filePath);
      return result?.accessible || false;
    }
    
    console.warn('checkFileAccess method is not available in the electron API');
    return false;
  } catch (error) {
    console.error('Error checking file access:', error);
    return false;
  }
};
