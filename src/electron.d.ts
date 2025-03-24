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
  
  // Secure API key management
  setApiKey?: (service: string, key: string) => Promise<{ success: boolean; error?: string }>;
  getApiKey?: (service: string) => Promise<{ success: boolean; key?: string; error?: string }>;
  hasApiKey?: (service: string) => Promise<{ success: boolean; hasKey: boolean; error?: string }>;
  deleteApiKey?: (service: string) => Promise<{ success: boolean; error?: string }>;

  // Analytics settings
  getAnalyticsConsent?: () => Promise<boolean>;
  setAnalyticsConsent?: (consent: boolean) => Promise<boolean>;
  onAnalyticsConsentChanged?: (callback: (consent: boolean) => void) => () => void;
  
  // App information
  appVersion?: string;

  // Added methods
  convertImageToBase64?: (filePath: string) => Promise<string>;
  callOpenAI?: (payload: any) => Promise<any>;
  saveMediaData?: (data: any) => Promise<any>;
  
  // Menu event handlers
  onImportFiles?: (callback: (filePaths: string[]) => void) => () => void;
  onOpenStorageLocation?: (callback: () => void) => () => void;
  onOpenSettings?: (callback: () => void) => () => void;
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