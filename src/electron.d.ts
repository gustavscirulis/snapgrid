
interface ElectronAPI {
  saveImage: (data: {
    id: string;
    dataUrl: string;
    metadata: Record<string, any>;
    isVideo?: boolean;
    extension?: string | null;
  }) => Promise<{ success: boolean; path?: string; error?: string }>;
  
  saveVideoFile: (data: {
    id: string;
    buffer: number[];
    extension: string;
    metadata: Record<string, any>;
  }) => Promise<{ success: boolean; path?: string; error?: string }>;
  
  saveUrlCard: (data: {
    id: string;
    metadata: Record<string, any>;
  }) => Promise<{ success: boolean; path?: string; error?: string }>;
  
  loadImages: () => Promise<any[]>;
  
  deleteImage: (id: string) => Promise<{ success: boolean; error?: string }>;
}

declare global {
  interface Window {
    electron: ElectronAPI;
  }
}

export {};
