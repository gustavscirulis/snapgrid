
// Helper functions for Electron interaction

/**
 * Checks if the application is running in Electron environment
 */
export function isElectronEnvironment(): boolean {
  const isRunningInElectron = typeof window !== 'undefined' && 
                              window.electron !== undefined && 
                              window.electron !== null;
                              
  console.log("isElectronEnvironment check:", {
    windowExists: typeof window !== 'undefined',
    electronExists: typeof window !== 'undefined' && typeof window.electron !== 'undefined',
    electronValue: typeof window !== 'undefined' ? window.electron : undefined
  });
  
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
      return await window.electron.checkFileAccess(filePath);
    }
    return false;
  } catch (error) {
    console.error("Error checking file access:", error);
    return false;
  }
}
