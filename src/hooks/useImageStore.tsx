import { useState, useCallback, useEffect } from "react";
import { analyzeImage, analyzeVideoFrames, hasApiKey } from "@/services/aiAnalysisService";
import { toast } from "sonner";
import { getVideoDimensions, captureVideoFrames } from '../lib/videoUtils';
import { sendAnalyticsEvent } from "@/services/analyticsService";

export type ImageItemType = "image" | "video" | "link"; // Added 'link' type

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
  imageSummary?: string;
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
  // Context description for the entire image
  imageContext?: string;
  // Link-specific preview fields
  ogImageUrl?: string;
  faviconUrl?: string;
}


import { fetchLinkPreview } from "@/lib/linkPreview";

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
          // Ensure these are included for link cards
          ogImageUrl: media.ogImageUrl,
          faviconUrl: media.faviconUrl,
          url: media.url,
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
    // Early return if no API key available
    const hasKey = await hasApiKey();
    if (!hasKey) return media;

    try {
      let analysis;
      let isAnalyzingVideo = false;

      // Handle different media types
      if (media.type === "image") {
        // For images, use the standard analysis
        analysis = await analyzeImage(dataUrl);
      } else if (media.type === "video") {
        // For videos, capture frames and analyze them
        isAnalyzingVideo = true;
        try {
          // Capture frames at 33% and 66% of the video duration
          const frames = await captureVideoFrames(dataUrl);
          // Analyze the captured frames
          analysis = await analyzeVideoFrames(frames);
        } catch (frameError) {
          console.error("Failed to capture or analyze video frames:", frameError);
          throw new Error("Failed to analyze video: " + (frameError instanceof Error ? frameError.message : 'Unknown error'));
        }
      } else {
        // Unsupported media type
        return media;
      }
      
      // Extract the imageContext from the first pattern (should be the same for all patterns)
      const imageContext = analysis[0]?.imageContext || '';
      
      const patternTags = analysis
        .map(pattern => {
          const name = pattern.pattern || pattern.name;
          if (!name) return null;
          
          return { 
            name, 
            confidence: pattern.confidence,
            imageContext: pattern.imageContext,
            imageSummary: pattern.imageSummary
          } as PatternTag;
        })
        .filter((tag): tag is PatternTag => tag !== null);

      const updatedMedia = { 
        ...media, 
        patterns: patternTags, 
        isAnalyzing: false,
        imageContext: imageContext // Set imageContext at the image level
      };

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
          toast.error(`Failed to save ${isAnalyzingVideo ? 'video' : 'image'} analysis`);
        }
      }

      return updatedMedia;
    } catch (error) {
      console.error('Media analysis failed:', error);
      toast.error("Analysis failed: " + (error instanceof Error ? error.message : 'Unknown error'));
      
      const updatedMedia = { ...media, isAnalyzing: false, error: 'Analysis failed' };
      
      // Make sure to save the error state in metadata
      if (isElectron && window.electron && savedFilePath) {
        try {
          await window.electron.updateMetadata({
            id: updatedMedia.id,
            metadata: {
              ...updatedMedia,
              filePath: savedFilePath
            }
          });
        } catch (metadataError) {
          console.error("Failed to update error state metadata:", metadataError);
        }
      }
      
      return updatedMedia;
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

        // Send analytics event for file added
        sendAnalyticsEvent('file-added', {
          type: media.type,
          width: media.width,
          height: media.height,
          fileSize: file.size,
          source: 'drag-drop'
        });
      }

      // Check if API key exists before attempting analysis
      const hasKey = await hasApiKey();
      if (hasKey) {
        // Only set analyzing state and attempt analysis if API key exists
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
      const sortedImages = [...(loadedImages || [])].sort((a, b) =>
  new Date(b.createdAt || 0).getTime() - new Date(a.createdAt || 0).getTime()
);
setImages(sortedImages);
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
          setImages(prevImages => [media, ...prevImages]);

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
          
          // Check if API key exists before attempting analysis
          const hasKey = await hasApiKey();
          if (hasKey) {
            // Only set analyzing state and attempt analysis if API key exists
            media = { ...media, isAnalyzing: true };
            setImages(prevImages => prevImages.map(img => img.id === media.id ? media : img));
          
            try {
              // For images, convert to base64 for analysis
              if (!isVideo) {
                const base64 = await window.electron.convertImageToBase64(result.path);
                const analyzedMedia = await analyzeAndUpdateImage(media, base64, result.path);
                setImages(prevImages => prevImages.map(img => img.id === media.id ? analyzedMedia : img));
              } else {
                // For videos, use the local file URL
                const localFileUrl = `local-file://${result.path}`;
                const analyzedMedia = await analyzeAndUpdateImage(media, localFileUrl, result.path);
                setImages(prevImages => prevImages.map(img => img.id === media.id ? analyzedMedia : img));
              }
            } catch (analyzeError) {
              console.error("Failed to analyze imported media:", analyzeError);
              // Update the media item to show error state
              const errorMedia = { ...media, isAnalyzing: false, error: 'Analysis failed' };
              setImages(prevImages => prevImages.map(img => img.id === media.id ? errorMedia : img));
              
              // Make sure the error state is saved to disk
              if (window.electron) {
                try {
                  await window.electron.updateMetadata({
                    id: errorMedia.id,
                    metadata: {
                      ...errorMedia,
                      filePath: result.path
                    }
                  });
                } catch (metadataError) {
                  console.error("Failed to update error state metadata:", metadataError);
                }
              }
            }
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
  };

  const addLink = async (url: string) => {
    setIsUploading(true);
    const now = new Date();
    const id = `${now.getTime()}-${Math.random().toString(36).substr(2, 9)}`;
    // Insert temporary loading card
    const tempLinkItem: ImageItem = {
      id,
      type: "link",
      url,
      width: 400,
      height: 200,
      createdAt: now,
      title: url,
      isAnalyzing: true,
    };
    setImages(prev => [tempLinkItem, ...prev]);
    try {
      // Fetch preview info
      const preview = await fetchLinkPreview(url);
      let ogImageUrl = preview.ogImageUrl;
      let faviconUrl = preview.faviconUrl;
      if (isElectron && window.electron) {
        // Download thumbnails to disk and use local paths
        if (ogImageUrl) {
          const ogFilename = `${id}-og.png`;
          const ogRes = await window.electron.downloadImage(ogImageUrl, ogFilename);
          if (ogRes.success) {
            ogImageUrl = `local-file://${ogRes.filePath}`;
          }
        }
        if (faviconUrl) {
          const favFilename = `${id}-favicon.png`;
          const favRes = await window.electron.downloadImage(faviconUrl, favFilename);
          if (favRes.success) {
            faviconUrl = `local-file://${favRes.filePath}`;
          }
        }
      }
      const linkItem: ImageItem = {
        id,
        type: "link",
        url,
        width: 400,
        height: 200,
        createdAt: now,
        ogImageUrl,
        faviconUrl,
        title: preview.title,
        description: preview.description,
        isAnalyzing: false,
      };
      setImages(prev => prev.map(img => img.id === id ? linkItem : img));
      // Persist link card in Electron mode
      if (isElectron && window.electron) {
        await saveMediaToDisk(linkItem, "");
      }
      toast.success("Link saved to library");
    } catch (e) {
      setImages(prev => prev.filter(img => img.id !== id));
      toast.error("Failed to fetch link preview");
    } finally {
      setIsUploading(false);
    }
  };


  // Persist link cards to localStorage in browser mode
  useEffect(() => {
    if (!isElectron) {
      const linkCards = images.filter(img => img.type === 'link');
      localStorage.setItem('snapgrid_link_cards', JSON.stringify(linkCards));
    }
  }, [images, isElectron]);

  return {
    images,
    isUploading,
    isLoading,
    addImage,
    addLink,
    removeImage,
    undoDelete,
    canUndo: deletedItemsHistory.length > 0,
    importFromFilePath,
    retryAnalysis: async (imageId: string) => {
      // Find the media
      const mediaToAnalyze = images.find(img => img.id === imageId);
      if (!mediaToAnalyze) {
        console.error("Cannot retry analysis: Media not found");
        return;
      }

      // Skip analysis for link cards
      if (mediaToAnalyze.type === 'link') {
        return;
      }

      // Check if API key exists before attempting retry
      const hasKey = await hasApiKey();
      if (!hasKey) {
        toast.error("OpenAI API key not set. Please set an API key to use image analysis.");
        return;
      }

      // Set analyzing state
      setImages(prevImages => prevImages.map(img => 
        img.id === imageId ? { ...img, isAnalyzing: true, error: undefined } : img
      ));

      try {
        // Get the data URL for analysis
        let dataUrl;
        
        if (isElectron && mediaToAnalyze.actualFilePath) {
          if (mediaToAnalyze.type === "image") {
            // If in Electron mode and we have a file path, convert image to base64
            dataUrl = await window.electron.convertImageToBase64(mediaToAnalyze.actualFilePath);
          } else {
            // For videos, use the file URL directly
            dataUrl = `local-file://${mediaToAnalyze.actualFilePath}`;
          }
        } else if (mediaToAnalyze.url) {
          // Otherwise, use the URL directly (may be a data URL already)
          dataUrl = mediaToAnalyze.url;
        } else {
          throw new Error("No media data available for analysis");
        }
        
        // Perform analysis
        const analyzedMedia = await analyzeAndUpdateImage(mediaToAnalyze, dataUrl, mediaToAnalyze.actualFilePath);
        
        // Update image in the state
        setImages(prevImages => prevImages.map(img => img.id === imageId ? analyzedMedia : img));
      } catch (error) {
        console.error("Retry analysis failed:", error);
        
        // Create the updated media with error
        const errorMedia = { ...mediaToAnalyze, isAnalyzing: false, error: 'Analysis failed' };
        
        // Update error state in UI
        setImages(prevImages => prevImages.map(img => 
          img.id === imageId ? errorMedia : img
        ));
        
        // Persist error state to disk
        if (isElectron && window.electron && mediaToAnalyze.actualFilePath) {
          try {
            await window.electron.updateMetadata({
              id: errorMedia.id,
              metadata: {
                ...errorMedia,
                filePath: mediaToAnalyze.actualFilePath
              }
            });
          } catch (metadataError) {
            console.error("Failed to update error state metadata:", metadataError);
          }
        }
      }
    }
  };
}