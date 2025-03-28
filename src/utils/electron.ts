
/**
 * Utility functions for Electron-related operations
 */

/**
 * Check if the app is running in Electron environment
 */
export const isElectron = (): boolean => {
  try {
    // More robust check for Electron environment
    // First check if the electron property exists
    if (typeof window !== 'undefined' && 
        typeof window.electron !== 'undefined' && 
        window.electron !== null) {
      
      console.log('Electron API object detected:', window.electron);
      
      // Check if at least one method exists and is callable
      const hasOneMethod = Object.values(window.electron).some(
        value => typeof value === 'function'
      );
      
      return hasOneMethod;
    }
    return false;
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
 */
export const checkFileAccess = async (filePath: string): Promise<boolean> => {
  if (!isElectron()) {
    console.warn('File access check not available in browser mode');
    return false;
  }
  
  try {
    const result = await window.electron?.checkFileAccess(filePath);
    return result?.accessible || false;
  } catch (error) {
    console.error('Error checking file access:', error);
    return false;
  }
};
