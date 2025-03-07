
interface ElectronAPI {
  getAppStorageDir: () => Promise<string>;
  
  // Save media file (image or video) to filesystem
  saveImage: (data: { 
    id: string; 
    file: File;
    mimeType: string;
    thumbnailBlob?: Blob;
  }) => Promise<{ 
    success: boolean; 
    path?: string; 
    thumbnailPath?: string;
    error?: string 
  }>;
  
  // Get image data for analysis
  getImageData: (id: string) => Promise<string>; // Returns base64 string
  
  // Update metadata for a media item
  updateImageMetadata: (id: string, metadata: any) => Promise<{ 
    success: boolean; 
    error?: string 
  }>;
  
  // Load all media items
  loadImages: () => Promise<any[]>;
  
  // Delete a media item
  deleteImage: (id: string) => Promise<{ success: boolean; error?: string }>;
  
  // Save URL card
  saveUrlCard: (data: { id: string; metadata: any }) => Promise<{ success: boolean; error?: string }>;
  
  // Open storage directory
  openStorageDir: () => Promise<{ success: boolean; error?: string }>;
}

declare global {
  interface Window {
    electron: ElectronAPI;
  }
}

export {};
