interface SaveImageOptions {
  id: string;
  dataUrl: string;
  metadata: any;
  fileExtension?: string;
}

interface SaveImageResult {
  success: boolean;
  path?: string;
  error?: string;
}

interface SaveUrlCardOptions {
  id: string;
  metadata: any;
}

interface DeleteImageResult {
  success: boolean;
  error?: string;
}

interface RenameFileOptions {
  oldPath: string;
  newExtension: string;
}

interface RenameFileResult {
  success: boolean;
  newPath?: string;
  error?: string;
}

interface ElectronAPI {
  loadImages(): Promise<any[]>;
  saveImage(options: SaveImageOptions): Promise<SaveImageResult>;
  saveUrlCard(options: SaveUrlCardOptions): Promise<void>;
  deleteImage(id: string): Promise<DeleteImageResult>;
  renameFile(options: RenameFileOptions): Promise<RenameFileResult>;
}

declare global {
  interface Window {
    electron: ElectronAPI;
    ipcRenderer: any;
  }
}
