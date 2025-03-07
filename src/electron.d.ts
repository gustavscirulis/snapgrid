interface IElectronAPI {
  // Window control methods
  closeWindow?: () => void;
  minimizeWindow?: () => void;
  maximizeWindow?: () => void;
}

declare global {
  interface Window {
    electron?: IElectronAPI;
  }
}

export {};
