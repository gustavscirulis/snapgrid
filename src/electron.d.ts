
interface IElectronAPI {
  // Window control methods
  minimize?: () => void;
  maximize?: () => void;
  close?: () => void;
  
  // File system operations
  saveFile?: (content: string, defaultPath?: string) => Promise<string | null>;
  openFile?: () => Promise<string | null>;
  readFile?: (filePath: string) => Promise<string | null>;
  writeFile?: (filePath: string, content: string) => Promise<boolean>;
  
  // Image management operations
  loadImages?: () => Promise<any[]>;
  saveImage?: (data: { id: string; dataUrl: string; metadata: any }) => Promise<{ success: boolean; path?: string; error?: string }>;
  deleteImage?: (id: string) => Promise<{ success: boolean; error?: string }>;
  saveUrlCard?: (data: { id: string; metadata: any }) => Promise<{ success: boolean; error?: string }>;
  getAppStorageDir?: () => Promise<string>;
  openStorageDir?: () => Promise<{ success: boolean; error?: string }>;
  
  // File metadata
  getFileMetadata?: (filePath: string) => Promise<any>;
  
  // Browser functionality
  openUrl?: (url: string) => void;
  
  // File access check
  checkFileAccess?: (filePath: string) => Promise<boolean>;
  
  // Invoke OpenAI functionality
  invokeOpenAI: (params: { apiKey: string; imageUrl: string; model: string }) => Promise<{
    patterns?: Array<{ pattern: string; confidence: number }>;
    error?: string;
  }>;
}

declare global {
  interface Window {
    electron?: IElectronAPI;
  }
}

export {};
