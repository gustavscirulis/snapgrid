
interface IElectronAPI {
  // Window control methods
  minimize?: () => void;
  maximize?: () => void;
  close?: () => void;
  
  // File storage operations
  loadImages?: () => Promise<any[]>;
  saveImage?: (data: { id: string; file: File; metadata: any }) => Promise<{ success: boolean; path?: string; error?: string }>;
  saveVideo?: (data: { id: string; file: File; metadata: any }) => Promise<{ success: boolean; path?: string; error?: string }>;
  updateMetadata?: (data: { id: string; metadata: any }) => Promise<{ success: boolean; error?: string }>;
  deleteImage?: (id: string) => Promise<{ success: boolean; error?: string }>;
  saveUrlCard?: (data: { id: string; metadata: any }) => Promise<{ success: boolean; error?: string }>;
  getAppStorageDir?: () => Promise<string>;
  openStorageDir?: () => Promise<{ success: boolean; error?: string }>;
  
  // Browser functionality
  openUrl?: (url: string) => void;
}

declare global {
  interface Window {
    electron?: IElectronAPI;
  }
}

export {};
