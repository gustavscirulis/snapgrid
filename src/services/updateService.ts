import { useState, useEffect } from 'react';

export interface UpdateInfo {
  version: string;
  releaseDate?: string;
  releaseName?: string;
}

export interface DownloadProgress {
  percent: number;
  bytesPerSecond: number;
  transferred: number;
  total: number;
}

export type UpdateState =
  | { status: 'idle' }
  | { status: 'checking' }
  | { status: 'available'; info: UpdateInfo }
  | { status: 'downloading'; progress: DownloadProgress; info: UpdateInfo }
  | { status: 'ready'; info: UpdateInfo }
  | { status: 'error'; message: string };

export const useUpdateChecker = () => {
  const [updateState, setUpdateState] = useState<UpdateState>({ status: 'idle' });
  const [notAvailableCount, setNotAvailableCount] = useState(0);
  const isElectron = typeof window !== 'undefined' && !!window.electron;

  useEffect(() => {
    if (!isElectron) return;
    const el = window.electron!;
    const cleanups: Array<() => void> = [];

    if (el.onUpdaterChecking) {
      cleanups.push(el.onUpdaterChecking(() => setUpdateState({ status: 'checking' })));
    }
    if (el.onUpdaterUpdateAvailable) {
      cleanups.push(el.onUpdaterUpdateAvailable((info) =>
        setUpdateState({ status: 'available', info })
      ));
    }
    if (el.onUpdaterNotAvailable) {
      cleanups.push(el.onUpdaterNotAvailable(() => {
        setUpdateState({ status: 'idle' });
        setNotAvailableCount((c) => c + 1);
      }));
    }
    if (el.onUpdaterDownloadProgress) {
      cleanups.push(el.onUpdaterDownloadProgress((progress) =>
        setUpdateState((prev) => ({
          status: 'downloading' as const,
          progress,
          info: (prev.status === 'available' || prev.status === 'downloading')
            ? prev.info
            : { version: '' },
        }))
      ));
    }
    if (el.onUpdaterDownloaded) {
      cleanups.push(el.onUpdaterDownloaded((info) =>
        setUpdateState({ status: 'ready', info })
      ));
    }
    if (el.onUpdaterError) {
      cleanups.push(el.onUpdaterError((message) =>
        setUpdateState({ status: 'error', message })
      ));
    }

    return () => cleanups.forEach((fn) => fn());
  }, [isElectron]);

  const installUpdate = () => {
    window.electron?.installUpdate?.();
  };

  return { updateState, installUpdate, notAvailableCount };
};
