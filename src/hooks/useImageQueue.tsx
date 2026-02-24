import { useEffect, useRef } from "react";
import { queueService } from "@/services/queueService";

export interface UseImageQueueReturn {
  queueService: typeof queueService;
}

export function useImageQueue(
  onQueueImport: (filePath: string) => Promise<void>
): UseImageQueueReturn {
  // Use a ref so the effect doesn't re-run (and restart the watcher) when the callback changes
  const onQueueImportRef = useRef(onQueueImport);
  onQueueImportRef.current = onQueueImport;

  useEffect(() => {
    queueService.startWatching();

    const handleQueueImport = (event: CustomEvent) => {
      const { filePath } = event.detail;
      onQueueImportRef.current(filePath).then(() => {
        queueService.removeFile(filePath);
      }).catch((error) => {
        console.error("Queue import failed:", error);
      });
    };

    window.addEventListener('queue-import-file', handleQueueImport as EventListener);

    return () => {
      queueService.stopWatching();
      window.removeEventListener('queue-import-file', handleQueueImport as EventListener);
    };
  }, []);

  return {
    queueService,
  };
}