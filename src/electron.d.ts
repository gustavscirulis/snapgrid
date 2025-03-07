
declare global {
  interface Window {
    electron: {
      loadImages: () => Promise<any[]>;
      saveImage: (params: {
        id: string;
        dataUrl: string;
        metadata: any;
        extension?: string | null;
      }) => Promise<{ success: boolean; path?: string; error?: string }>;
      saveUrlCard: (params: {
        id: string;
        metadata: any;
      }) => Promise<{ success: boolean; path?: string; error?: string }>;
      deleteImage: (id: string) => Promise<{ success: boolean; error?: string }>;
    };
  }
}

export {};
