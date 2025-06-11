import { toast } from "@/hooks/use-toast";

export interface QueueStats {
  totalFiles: number;
  processing: boolean;
}

export class QueueService {
  private isProcessing = false;
  private queueWatcherCleanup: (() => void) | null = null;

  async startWatching(): Promise<void> {
    try {
      const result = await window.electron.queueStartWatching();
      if (result.success) {
        console.log('Queue watching started');
        
        // Set up listener for new files
        this.queueWatcherCleanup = window.electron.onQueueNewFile((filePath: string) => {
          console.log('New file detected in queue:', filePath);
          toast({
            title: "New image in queue",
            description: `Ready to import: ${filePath.split('/').pop()}`,
          });
          
          // Auto-process the file
          this.processFile(filePath);
        });
      } else {
        console.error('Failed to start queue watching:', result.error);
      }
    } catch (error) {
      console.error('Error starting queue watcher:', error);
    }
  }

  async stopWatching(): Promise<void> {
    try {
      if (this.queueWatcherCleanup) {
        this.queueWatcherCleanup();
        this.queueWatcherCleanup = null;
      }
      
      const result = await window.electron.queueStopWatching();
      if (result.success) {
        console.log('Queue watching stopped');
      } else {
        console.error('Failed to stop queue watching:', result.error);
      }
    } catch (error) {
      console.error('Error stopping queue watcher:', error);
    }
  }

  async getQueueStats(): Promise<QueueStats> {
    try {
      const result = await window.electron.queueListFiles();
      return {
        totalFiles: result.files?.length || 0,
        processing: this.isProcessing
      };
    } catch (error) {
      console.error('Error getting queue stats:', error);
      return { totalFiles: 0, processing: false };
    }
  }

  async processAllFiles(): Promise<void> {
    if (this.isProcessing) {
      console.log('Queue processing already in progress');
      return;
    }

    try {
      this.isProcessing = true;
      const result = await window.electron.queueListFiles();
      
      if (!result.success || !result.files.length) {
        console.log('No files in queue to process');
        return;
      }

      console.log(`Processing ${result.files.length} files from queue`);
      
      for (const filePath of result.files) {
        await this.processFile(filePath);
      }

      toast({
        title: "Queue processed",
        description: `Successfully imported ${result.files.length} images from queue`,
      });

    } catch (error) {
      console.error('Error processing queue:', error);
      toast({
        title: "Queue processing failed",
        description: "Failed to process some queued images",
        variant: "destructive",
      });
    } finally {
      this.isProcessing = false;
    }
  }

  private async processFile(filePath: string): Promise<void> {
    try {
      // Get file info from main process
      const fileResult = await window.electron.queueProcessFile(filePath);
      
      if (!fileResult.success) {
        console.error('Failed to get file info:', fileResult.error);
        return;
      }

      // Import the file using existing import logic
      // We'll need to trigger the addImage function from useImageStore
      const event = new CustomEvent('queue-import-file', {
        detail: { filePath: fileResult.filePath }
      });
      window.dispatchEvent(event);

    } catch (error) {
      console.error('Error processing queued file:', error);
    }
  }

  async removeFile(filePath: string): Promise<void> {
    try {
      const result = await window.electron.queueRemoveFile(filePath);
      if (!result.success) {
        console.error('Failed to remove file from queue:', result.error);
      }
    } catch (error) {
      console.error('Error removing file from queue:', error);
    }
  }
}

// Export singleton instance
export const queueService = new QueueService();