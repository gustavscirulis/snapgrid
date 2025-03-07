
declare global {
  interface Window {
    electron: {
      saveImage: (params: { id: string; dataUrl: string; metadata: any }) => Promise<{ success: boolean; path?: string; error?: string }>;
      saveVideoFile: (params: { id: string; buffer: number[]; extension: string; metadata: any }) => Promise<{ success: boolean; path?: string; error?: string }>;
      saveUrlCard: (params: { id: string; metadata: any }) => Promise<{ success: boolean; error?: string }>;
      loadImages: () => Promise<any[]>;
      deleteImage: (id: string) => Promise<{ success: boolean; error?: string }>;
      getVideoStreamUrl: (id: string) => string;
    }
  }
}

export {};
