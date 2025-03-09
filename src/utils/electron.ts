
// Helper functions for Electron interaction

/**
 * Checks if the application is running in Electron environment
 */
export function isElectronEnvironment(): boolean {
  // Check if window.electron exists without accessing properties
  // that might not exist
  const windowExists = typeof window !== 'undefined';
  const electronExists = windowExists && window.electron !== undefined;
  
  // Look for Electron in user agent as a fallback detection method
  const userAgentHasElectron = windowExists && 
    typeof window.navigator !== 'undefined' && 
    /electron/i.test(window.navigator.userAgent);
    
  const isRunningInElectron = electronExists || userAgentHasElectron;
  
  return isRunningInElectron;
}

/**
 * Checks if a file path is accessible in the Electron environment
 * @param filePath Path to check
 */
export async function isFileAccessible(filePath: string): Promise<boolean> {
  if (!isElectronEnvironment() || !window.electron) {
    return false;
  }
  
  try {
    // Only call checkFileAccess if it exists
    if (window.electron && typeof window.electron.checkFileAccess === 'function') {
      const result = await window.electron.checkFileAccess(filePath);
      return result;
    }
    return false;
  } catch (error) {
    console.error("Error checking file access:", error);
    return false;
  }
}
