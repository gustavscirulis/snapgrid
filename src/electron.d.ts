
// Type definitions for Electron API

// Interface for saved image metadata
interface SaveImageResult {
  success: boolean;
  path?: string;
  error?: string;
}

// Interface for deleting image
interface DeleteImageResult {
  success: boolean;
  error?: string;
}

// Interface for saving URL card
interface SaveUrlCardResult {
  success: boolean;
  error?: string;
}

// Interface for the electron global
interface ElectronAPI {
  saveImage: (data: { id: string; dataUrl: string | null; metadata: any }) => Promise<SaveImageResult>;
  loadImages: () => Promise<any[]>;
  deleteImage: (id: string) => Promise<DeleteImageResult>;
  saveUrlCard: (data: { id: string; metadata: any }) => Promise<SaveUrlCardResult>;
  getAppStorageDir: () => Promise<string>;
  openStorageDir: () => Promise<void>;
}

declare global {
  interface Window {
    electron: ElectronAPI;
  }
}

export {};
