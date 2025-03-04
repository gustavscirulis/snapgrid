
interface ElectronAPI {
  getAppStorageDir: () => Promise<string>;
  saveImage: (data: { id: string; dataUrl: string; metadata: any }) => Promise<{ success: boolean; path?: string; error?: string }>;
  loadImages: () => Promise<any[]>;
  deleteImage: (id: string) => Promise<{ success: boolean; error?: string }>;
  saveUrlCard: (data: { id: string; metadata: any }) => Promise<{ success: boolean; error?: string }>;
}

declare global {
  interface Window {
    electron?: ElectronAPI;
  }
}

export {};
