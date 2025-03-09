
declare global {
  interface Window {
    electron: {
      close: () => void;
      minimize: () => void;
      maximize: () => void;
      loadImages: () => Promise<any[]>;
      saveImage: (data: { id: string; dataUrl: string; metadata: any }) => Promise<{ success: boolean; path?: string; error?: string }>;
      saveUrlCard: (data: { id: string; metadata: any }) => Promise<{ success: boolean; error?: string }>;
      deleteImage: (id: string) => Promise<{ success: boolean; error?: string }>;
      checkFileAccess: (path: string) => Promise<boolean>;
      updateImageMetadata: (data: { id: string; metadata: any }) => Promise<{ success: boolean; error?: string }>;
    };
  }
}

export {};
