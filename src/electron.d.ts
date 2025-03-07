
interface ElectronAPI {
  loadImages: () => Promise<any[]>;
  saveImage: (data: { 
    id: string; 
    dataUrl: string; 
    metadata: any; 
  }) => Promise<{ 
    success: boolean; 
    path?: string; 
    error?: string; 
  }>;
  saveUrlCard: (data: { 
    id: string; 
    metadata: any; 
  }) => Promise<{ 
    success: boolean; 
    error?: string; 
  }>;
  deleteImage: (id: string) => Promise<{ 
    success: boolean; 
    error?: string; 
  }>;
  getStoragePath: () => Promise<string>;
}

declare global {
  interface Window {
    electron: ElectronAPI;
  }
}

export {};
