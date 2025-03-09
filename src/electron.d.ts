
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
