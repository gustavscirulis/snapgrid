
// Fix for the checkFileAccess method that's causing build errors
// We'll add a type guard to check if the function exists before calling it

export const checkFileExists = async (filePath: string): Promise<boolean> => {
  if (window.electron) {
    if (typeof window.electron.checkFileAccess === 'function') {
      return await window.electron.checkFileAccess(filePath);
    } else {
      console.warn('checkFileAccess function not available in electron API');
      return false;
    }
  }
  return false;
};
