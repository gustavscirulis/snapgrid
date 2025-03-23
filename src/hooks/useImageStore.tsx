import { useState, useCallback, useEffect } from "react";
import { analyzeImage, hasApiKey } from "@/services/aiAnalysisService";
import { toast } from "sonner";
import { getVideoDimensions } from '../lib/videoUtils';

export type ImageItemType = "image" | "video";

// Helper function to get filename from a path
const getFilenameFromPath = (filePath: string): string => {
  // Handle both Windows and Unix paths
  const parts = filePath.split(/[\\/]/);
  return parts[parts.length - 1] || filePath;
};

export interface PatternTag {
  name: string;
  confidence: number;
  imageContext?: string;
}

export interface ImageItem {
  id: string;
  type: ImageItemType;
  url: string;
  width: number;
  height: number;
  createdAt: Date;
  title?: string;
  description?: string;
  patterns?: PatternTag[];
  isAnalyzing?: boolean;
  error?: string;
  // File system related props
  actualFilePath?: string;
  useDirectPath?: boolean;
  // Video specific props
  duration?: number;
  posterUrl?: string;
}

export function useImageStore() {
  const [images, setImages] = useState<ImageItem[]>([]);
  const [trashItems, setTrashItems] = useState<ImageItem[]>([]);
  const [isUploading, setIsUploading] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [isElectron, setIsElectron] = useState(false);
  const [deletedItemsHistory, setDeletedItemsHistory] = useState<ImageItem[]>([]);

  useEffect(() => {
    const isRunningInElectron = window &&
      typeof window.electron !== 'undefined' &&
      window.electron !== null;

    setIsElectron(isRunningInElectron);

    const loadImages = async () => {
      try {
        if (isRunningInElectron) {
          const [loadedImages, loadedTrashItems] = await Promise.all([
            window.electron.loadImages(),
            window.electron.listTrash()
          ]);
          // Sort by createdAt with newest first
          const sortedImages = [...(loadedImages || [])].sort((a, b) =>
            new Date(b.createdAt || 0).getTime() - new Date(a.createdAt || 0).getTime()
          );
          setImages(sortedImages);
          setTrashItems(loadedTrashItems || []);
        } else {
          setImages([]);
          setTrashItems([]);
          toast.warning("Running in browser mode. Images will not be saved permanently.");
        }
      } catch (error) {
        console.error("Error loading images:", error);
        toast.error("Failed to load images");
      }
      setIsLoading(false);
    };

    loadImages();
  }, []);

  const readFileAsDataURL = (file: File): Promise<string> => {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result as string);
      reader.onerror = reject;
      reader.readAsDataURL(file);
    });
  };

  const getImageDimensions = async (dataUrl: string): Promise<{ width: number; height: number }> => {
    return new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => resolve({ width: img.width, height: img.height });
      img.onerror = reject;
      img.src = dataUrl;
    });
  };

  const saveMediaToDisk = async (media: ImageItem, dataUrl: string): Promise<string | undefined> => {
    if (!isElectron || !window.electron) return undefined;

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
  };

  const analyzeAndUpdateImage = async (media: ImageItem, dataUrl: string, savedFilePath?: string) => {
    if (media.type !== "image") return media;

    const hasKey = await hasApiKey();
    if (!hasKey) return media;

    try {
      const analysis = await analyzeImage(dataUrl);
      const patternTags = analysis
        .map(pattern => {
          const name = pattern.pattern || pattern.name;
          if (!name) return null;
          
          return { 
            name, 
            confidence: pattern.confidence,
            imageContext: pattern.imageContext 
          } as PatternTag;
        })
        .filter((tag): tag is PatternTag => tag !== null);

      const updatedMedia = { ...media, patterns: patternTags, isAnalyzing: false };

      if (isElectron && window.electron && savedFilePath) {
        try {
          await window.electron.updateMetadata({
            id: updatedMedia.id,
            metadata: {
              ...updatedMedia,
              filePath: savedFilePath
            }
          });
        } catch (error) {
          console.error("Failed to update metadata:", error);
          toast.error("Failed to save pattern analysis");
        }
      }

      return updatedMedia;
    } catch (error) {
      console.error('Image analysis failed:', error);
      toast.error("Image analysis failed: " + (error instanceof Error ? error.message : 'Unknown error'));
      return { ...media, isAnalyzing: false, error: 'Analysis failed' };
    }
  };

  const addImage = useCallback(async (file: File) => {
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
      setImages(prevImages => [media, ...prevImages]);

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
        setImages(prevImages => [media, ...prevImages.filter(img => img.id !== media.id)]);
      }

      // Analyze image if applicable - this can also happen in the background
      if (media.type === "image") {
        media = { ...media, isAnalyzing: true };
        setImages(prevImages => prevImages.map(img => img.id === media.id ? media : img));
        
        const analyzedMedia = await analyzeAndUpdateImage(media, dataUrl, savedFilePath);
        setImages(prevImages => prevImages.map(img => img.id === media.id ? analyzedMedia : img));
      }
    } catch (error) {
      console.error("Error adding media:", error);
      toast.error("Failed to add media: " + (error instanceof Error ? error.message : 'Unknown error'));
      setIsUploading(false); // Make sure to reset on error
    }
  }, [isElectron]);

  const removeImage = useCallback(async (id: string) => {
    try {
      const itemToDelete = images.find(img => img.id === id);
      if (!itemToDelete) return;

      if (isElectron) {
        await window.electron.deleteImage(id);
        // Update trash items list
        const updatedTrashItems = await window.electron.listTrash();
        setTrashItems(updatedTrashItems);
      }
      setImages(prevImages => prevImages.filter(img => img.id !== id));
      // Add to history
      setDeletedItemsHistory(prev => [...prev, itemToDelete]);
    } catch (error) {
      console.error("Failed to delete image:", error);
      toast.error("Failed to delete image");
    }
  }, [isElectron, images]);

  const undoDelete = useCallback(async () => {
    if (deletedItemsHistory.length === 0 || !isElectron) return;

    try {
      // Get the last deleted item
      const lastDeletedItem = deletedItemsHistory[deletedItemsHistory.length - 1];
      await window.electron.restoreFromTrash(lastDeletedItem.id);
      
      // Reload images and trash items
      const [loadedImages, loadedTrashItems] = await Promise.all([
        window.electron.loadImages(),
        window.electron.listTrash()
      ]);
      setImages(loadedImages);
      setTrashItems(loadedTrashItems);
      // Remove the last item from history
      setDeletedItemsHistory(prev => prev.slice(0, -1));
    } catch (error) {
      console.error("Failed to restore image:", error);
      toast.error("Failed to restore image");
    }
  }, [deletedItemsHistory, isElectron]);

  const emptyTrash = useCallback(async () => {
    if (!isElectron) return;

    try {
      await window.electron.emptyTrash();
      setTrashItems([]);
      // Clear the history when emptying trash
      setDeletedItemsHistory([]);
    } catch (error) {
      console.error("Failed to empty trash:", error);
      toast.error("Failed to empty trash");
    }
  }, [isElectron]);

  // Add this function to handle importing files directly from the file system
  // This will be used by the menu file import function
  const importFromFilePath = async (filePath: string) => {
    if (!isElectron || !window.electron) {
      console.error("Cannot import file directly in browser mode");
      toast.error("Cannot import file directly in browser mode");
      return;
    }
    
    try {
      // For browser testing - this won't actually work in browser mode
      if (!isElectron) return;
      
      // Get the file extension
      const fileExt = filePath.toLowerCase().split('.').pop() || '';
      
      // Determine if this is a video or image based on extension
      const isVideo = ['mp4', 'webm', 'mov', 'avi'].includes(fileExt);
      const id = `${isVideo ? 'vid' : 'img'}_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
      
      // Set a loading state for better UI feedback
      setIsUploading(true);
      
      try {
        // Create a local file URL we can use to get dimensions
        const localFileUrl = `file://${filePath}`;
        
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
          setImages(prevImages => [media, ...prevImages]);
          
          // Set isUploading to false here before starting analysis
          // This allows users to upload more images while analysis is running
          setIsUploading(false);
          
          // If it's an image, analyze it
          if (!isVideo) {
            media = { ...media, isAnalyzing: true };
            setImages(prevImages => prevImages.map(img => img.id === media.id ? media : img));
            
            try {
              // Convert to base64 for analysis
              const base64 = await window.electron.convertImageToBase64(result.path);
              const analyzedMedia = await analyzeAndUpdateImage(media, base64, result.path);
              setImages(prevImages => prevImages.map(img => img.id === media.id ? analyzedMedia : img));
            } catch (analyzeError) {
              console.error("Failed to analyze imported image:", analyzeError);
              // Update the media item to show error state
              const errorMedia = { ...media, isAnalyzing: false, error: 'Analysis failed' };
              setImages(prevImages => prevImages.map(img => img.id === media.id ? errorMedia : img));
            }
          }
          
          // Remove success toast
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
  };

  return {
    images,
    trashItems,
    isUploading,
    isLoading,
    isElectron,
    addImage,
    removeImage,
    emptyTrash,
    undoDelete,
    importFromFilePath,
    canUndo: deletedItemsHistory.length > 0
  };
}