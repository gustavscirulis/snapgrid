
// Make sure we have 'electron' declared as an optional property
interface Window {
  electron?: {
    loadImages: () => Promise<any[]>;
    saveImage: (data: { id: string; dataUrl: string; metadata: any }) => Promise<{ success: boolean; path?: string; error?: string }>;
    saveUrlCard: (data: { id: string; metadata: any }) => Promise<{ success: boolean }>;
    deleteImage: (id: string) => Promise<{ success: boolean }>;
  };
}
