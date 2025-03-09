
// Helper functions for Electron interaction

/**
 * Checks if the application is running in Electron environment
 */
export function isElectronEnvironment(): boolean {
  // Check if window.electron exists without accessing properties
  // that might not exist
  const windowExists = typeof window !== 'undefined';
  const electronExists = windowExists && window.electron !== undefined;
  
  console.log("isElectronEnvironment check:", {
    windowExists,
    electronExists,
    electronValue: windowExists ? window.electron : undefined,
    electronKeys: windowExists && window.electron ? Object.keys(window.electron) : [],
    userAgent: windowExists ? window.navigator.userAgent : ''
  });
  
  // Look for Electron in user agent as a fallback detection method
  const userAgentHasElectron = windowExists && 
    typeof window.navigator !== 'undefined' && 
    /electron/i.test(window.navigator.userAgent);
    
  const isRunningInElectron = electronExists || userAgentHasElectron;
  
  console.log(`Final Electron detection result: ${isRunningInElectron}`);
  return isRunningInElectron;
}

/**
 * Checks if a file path is accessible in the Electron environment
 * @param filePath Path to check
 */
export async function isFileAccessible(filePath: string): Promise<boolean> {
  if (!isElectronEnvironment() || !window.electron) {
    console.log("File access check failed: Not in Electron environment or window.electron not available");
    return false;
  }
  
  try {
    // Only call checkFileAccess if it exists
    if (window.electron && typeof window.electron.checkFileAccess === 'function') {
      const result = await window.electron.checkFileAccess(filePath);
      console.log(`File access check for ${filePath}: ${result}`);
      return result;
    }
    console.log("checkFileAccess method not available on window.electron");
    return false;
  } catch (error) {
    console.error("Error checking file access:", error);
    return false;
  }
}
