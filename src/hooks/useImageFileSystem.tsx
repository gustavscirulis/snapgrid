import { useState, useCallback } from "react";
import { toast } from "sonner";
import { getVideoDimensions } from '../lib/videoUtils';
import { sendAnalyticsEvent } from "@/services/analyticsService";
import { ImageItem } from "./useImageStore";

export interface UseImageFileSystemReturn {
  isUploading: boolean;
  setIsUploading: React.Dispatch<React.SetStateAction<boolean>>;
  readFileAsDataURL: (file: File) => Promise<string>;
  getImageDimensions: (dataUrl: string) => Promise<{ width: number; height: number }>;
  saveMediaToDisk: (media: ImageItem, dataUrl: string) => Promise<string | undefined>;
  addImageFromFile: (
    file: File,
    onAddToCollection: (media: ImageItem) => void,
    onAnalyze: (media: ImageItem, dataUrl: string, savedFilePath?: string) => Promise<ImageItem>
  ) => Promise<void>;
  importFromFilePath: (
    filePath: string,
    onAddToCollection: (media: ImageItem) => void,
    onAnalyze: (media: ImageItem, dataUrl: string, savedFilePath?: string) => Promise<ImageItem>
  ) => Promise<void>;
}

// Helper function to get filename from a path
const getFilenameFromPath = (filePath: string): string => {
  // Handle both Windows and Unix paths
  const parts = filePath.split(/[\\/]/);
  return parts[parts.length - 1] || filePath;
};

export function useImageFileSystem(): UseImageFileSystemReturn {
  const [isUploading, setIsUploading] = useState(false);

  const readFileAsDataURL = useCallback((file: File): Promise<string> => {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result as string);
      reader.onerror = reject;
      reader.readAsDataURL(file);
    });
  }, []);

  const getImageDimensions = useCallback(async (dataUrl: string): Promise<{ width: number; height: number }> => {
    return new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => resolve({ width: img.width, height: img.height });
      img.onerror = reject;
      img.src = dataUrl;
    });
  }, []);

  const saveMediaToDisk = useCallback(async (media: ImageItem, dataUrl: string): Promise<string | undefined> => {
    try {
      const result = await window.electron.saveImage({
        id: media.id,
        dataUrl: dataUrl,
        metadata: {
          width: media.width,
          height: media.height,
          createdAt: media.createdAt,
          title: media.title,
          description: media.description,
          type: media.type,
          duration: media.duration,
          posterUrl: media.posterUrl,
        }
      });

      if (result.success && result.path) {
        return result.path;
      } else {
        throw new Error(result.error || "Unknown error");
      }
    } catch (error) {
      console.error("Failed to save media to filesystem:", error);
      toast.error("Failed to save media to disk");
      return undefined;
    }
  }, []);

  const addImageFromFile = useCallback(async (
    file: File,
    onAddToCollection: (media: ImageItem) => void,
    onAnalyze: (media: ImageItem, dataUrl: string, savedFilePath?: string) => Promise<ImageItem>
  ) => {
    setIsUploading(true);

    try {
      const isVideo = file.type.startsWith('video/');
      const id = `${isVideo ? 'vid' : 'img'}_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
      const dataUrl = await readFileAsDataURL(file);

      let media: ImageItem = {
        id,
        type: isVideo ? "video" : "image",
        url: dataUrl,
        width: 0,
        height: 0,
        createdAt: new Date(),
      };

      // Get dimensions and additional data
      if (isVideo) {
        const videoData = await getVideoDimensions(dataUrl);
        media = { ...media, ...videoData };
      } else {
        const dimensions = await getImageDimensions(dataUrl);
        media = { ...media, ...dimensions };
      }

      // Add to images list
      onAddToCollection(media);

      // Set isUploading to false here so other uploads can proceed
      setIsUploading(false);

      // Save to disk if in Electron - this can continue in the background
      const savedFilePath = await saveMediaToDisk(media, dataUrl);
      if (savedFilePath) {
        media = {
          ...media,
          actualFilePath: savedFilePath,
          url: `local-file://${savedFilePath}`,
          useDirectPath: true
        };
        onAddToCollection(media);

        // Send analytics event for file added
        sendAnalyticsEvent('file-added', {
          type: media.type,
          width: media.width,
          height: media.height,
          fileSize: file.size,
          source: 'drag-drop'
        });
      }

      // Trigger analysis
      try {
        const analyzedMedia = await onAnalyze(media, dataUrl, savedFilePath);
        onAddToCollection(analyzedMedia);
      } catch (error) {
        console.error("Analysis failed:", error);
        // Analysis failure is handled in the analysis hook
      }
    } catch (error) {
      console.error("Error adding media:", error);
      toast.error("Failed to add media: " + (error instanceof Error ? error.message : 'Unknown error'));
      setIsUploading(false); // Make sure to reset on error
    }
  }, [readFileAsDataURL, getImageDimensions, saveMediaToDisk]);

  const importFromFilePath = useCallback(async (
    filePath: string,
    onAddToCollection: (media: ImageItem) => void,
    onAnalyze: (media: ImageItem, dataUrl: string, savedFilePath?: string) => Promise<ImageItem>
  ) => {
    try {
      // Get the file extension
      const fileExt = filePath.toLowerCase().split('.').pop() || '';
      
      // Determine if this is a video or image based on extension
      const isVideo = ['mp4', 'webm', 'mov', 'avi'].includes(fileExt);
      const id = `${isVideo ? 'vid' : 'img'}_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
      
      // Set a loading state for better UI feedback
      setIsUploading(true);
      
      try {
        // IMPORTANT: Always use local-file:// protocol for local files. file:// protocol does not work locally.
        const localFileUrl = `local-file://${filePath}`;
        
        // Create basic media item with defaults
        let media: ImageItem = {
          id,
          type: isVideo ? "video" : "image",
          url: localFileUrl, // Temporary URL
          width: 0,
          height: 0,
          createdAt: new Date(),
        };
        
        // Try to get dimensions if possible
        if (isVideo) {
          try {
            // For videos, use the video utils
            const videoData = await getVideoDimensions(localFileUrl);
            media = { ...media, ...videoData };
          } catch (dimError) {
            console.error("Error getting video dimensions:", dimError);
            // Continue with default dimensions
          }
        } else {
          try {
            // For images, convert to base64 to get dimensions
            const base64 = await window.electron.convertImageToBase64(filePath);
            const dimensions = await getImageDimensions(base64);
            media = { ...media, ...dimensions };
          } catch (dimError) {
            console.error("Error getting image dimensions:", dimError);
            // Continue with default dimensions
          }
        }
        
        // Save to disk directly using the file path
        const result = await window.electron.saveImage({
          id: media.id,
          dataUrl: filePath, // Use the file path directly
          metadata: {
            width: media.width,
            height: media.height,
            createdAt: media.createdAt,
            title: media.title || getFilenameFromPath(filePath), // Use filename as title
            description: media.description,
            type: media.type,
            duration: media.duration,
            posterUrl: media.posterUrl,
            originalPath: filePath // Include the original path
          }
        });
        
        if (result.success && result.path) {
          console.log("Media saved successfully at:", result.path);
          media = {
            ...media,
            actualFilePath: result.path,
            url: `local-file://${result.path}`,
            useDirectPath: true
          };
          
          // Add to image list
          onAddToCollection(media);

          // Send analytics event for file added
          sendAnalyticsEvent('file-added', {
            type: media.type,
            width: media.width,
            height: media.height,
            source: 'file-system',
            originalPath: filePath
          });
          
          // Set isUploading to false here before starting analysis
          // This allows users to upload more images while analysis is running
          setIsUploading(false);
          
          // Trigger analysis
          try {
            // For images, convert to base64 for analysis
            if (!isVideo) {
              const base64 = await window.electron.convertImageToBase64(result.path);
              const analyzedMedia = await onAnalyze(media, base64, result.path);
              onAddToCollection(analyzedMedia);
            } else {
              // For videos, use the local file URL
              const localFileUrl = `local-file://${result.path}`;
              const analyzedMedia = await onAnalyze(media, localFileUrl, result.path);
              onAddToCollection(analyzedMedia);
            }
          } catch (analyzeError) {
            console.error("Failed to analyze imported media:", analyzeError);
            // Analysis failure is handled in the analysis hook
          }
        } else {
          throw new Error(result.error || "Unknown error");
        }
      } catch (error) {
        console.error("Failed to import media:", error);
        toast.error("Failed to import media");
        setIsUploading(false);
      }
    } catch (error) {
      console.error("Error importing file:", error);
      toast.error("Failed to import file: " + (error instanceof Error ? error.message : 'Unknown error'));
      setIsUploading(false);
    }
  }, [getImageDimensions]);

  return {
    isUploading,
    setIsUploading,
    readFileAsDataURL,
    getImageDimensions,
    saveMediaToDisk,
    addImageFromFile,
    importFromFilePath,
  };
}