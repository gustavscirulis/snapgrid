import { useEffect } from "react";
import { queueService } from "@/services/queueService";

export interface UseImageQueueReturn {
  queueService: typeof queueService;
}

export function useImageQueue(
  onQueueImport: (filePath: string) => Promise<void>
): UseImageQueueReturn {
  
  useEffect(() => {
    // Initialize queue service
    queueService.startWatching();

    // Listen for queue import events
    const handleQueueImport = (event: CustomEvent) => {
      const { filePath } = event.detail;
      onQueueImport(filePath).then(() => {
        // Remove the processed file from queue
        queueService.removeFile(filePath);
      }).catch((error) => {
        console.error("Queue import failed:", error);
        // Optionally handle failed imports (retry logic, etc.)
      });
    };

    window.addEventListener('queue-import-file', handleQueueImport as EventListener);
    
    return () => {
      queueService.stopWatching();
      window.removeEventListener('queue-import-file', handleQueueImport as EventListener);
    };
  }, [onQueueImport]);

  return {
    queueService,
  };
}