
declare global {
  interface Window {
    electron: {
      saveImage: (data: {
        id: string;
        dataUrl: string;
        metadata: Record<string, any>;
        extension?: string | null;
        isVideo?: boolean;  // Add isVideo flag
      }) => Promise<{
        success: boolean;
        path?: string;
        error?: string;
      }>;
      saveUrlCard: (data: {
        id: string;
        metadata: Record<string, any>;
      }) => Promise<{
        success: boolean;
        error?: string;
      }>;
      loadImages: () => Promise<any[]>;
      deleteImage: (id: string) => Promise<{
        success: boolean;
        error?: string;
      }>;
      setApiKey: (key: string) => Promise<void>;
      getApiKey: () => Promise<string | null>;
    };
  }
}

export {};
