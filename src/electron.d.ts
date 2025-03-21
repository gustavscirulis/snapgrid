interface IElectronAPI {
  // Window control methods
  minimize?: () => void;
  maximize?: () => void;
  close?: () => void;

  // File storage operations
  loadImages?: () => Promise<any[]>;
  saveImage?: (data: { id: string; dataUrl: string; metadata: any }) => Promise<{ success: boolean; path?: string; error?: string }>;
  updateMetadata?: (data: { id: string; metadata: any }) => Promise<{ success: boolean; error?: string }>;
  deleteImage?: (id: string) => Promise<{ success: boolean; error?: string }>;
  restoreFromTrash?: (id: string) => Promise<{ success: boolean; error?: string }>;
  emptyTrash?: () => Promise<{ success: boolean; error?: string }>;
  listTrash?: () => Promise<any[]>;
  getTrashDir?: () => Promise<string>;
  getAppStorageDir?: () => Promise<string>;
  openStorageDir?: () => Promise<{ success: boolean; error?: string }>;
  checkFileAccess?: (filePath: string) => Promise<{ success: boolean; accessible: boolean; error?: string }>;

  // Browser functionality
  openUrl?: (url: string) => void;
  // Added methods
  convertImageToBase64?: (filePath: string) => Promise<string>;
  callOpenAI?: (apiKey: string, payload: any) => Promise<any>;
  saveMediaData?: (data: any) => Promise<any>;

}

// Define the protocol for local file access
declare global {
  interface Window {
    electron?: IElectronAPI;
  }
}

declare global {
  interface Window {
    electron?: IElectronAPI;
  }
}

export {};