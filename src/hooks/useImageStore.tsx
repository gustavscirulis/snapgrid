
import { useState, useCallback, useEffect } from "react";
import { analyzeImage, hasApiKey } from "@/services/aiAnalysisService";
import { toast } from "sonner";
import { getImageDimensions, getFileExtension, isVideoFile } from "@/lib/imageUtils";

export type MediaItemType = "image" | "video" | "url";

export interface PatternTag {
  name: string;
  confidence: number;
}

export interface MediaItem {
  id: string;
  type: MediaItemType;
  url: string;
  width: number;
  height: number;
  createdAt: Date;
  title?: string;
  thumbnailUrl?: string;
  sourceUrl?: string;
  patterns?: PatternTag[];
  isAnalyzing?: boolean;
  error?: string;
  actualFilePath?: string;
  fileExtension?: string;
}

export function useImageStore() {
  const [mediaItems, setMediaItems] = useState<MediaItem[]>([]);
  const [isUploading, setIsUploading] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [isElectron, setIsElectron] = useState(false);

  useEffect(() => {
    // More reliable detection for Electron
    const isRunningInElectron = window && 
      typeof window.electron !== 'undefined' && 
      window.electron !== null;
    
    console.log("useImageStore - Electron detection:", {
      electronExists: typeof window.electron !== 'undefined',
      electronValue: window.electron
    });
    
    setIsElectron(isRunningInElectron);
    
    const loadMediaItems = async () => {
      try {
        if (isRunningInElectron) {
          console.log("Loading media items from filesystem...");
          const loadedItems = await window.electron.loadImages();
          console.log("Loaded media items:", loadedItems.length);
          
          // Process loaded items to ensure video files have proper URL and type
          const processedItems = loadedItems.map(item => {
            // If it's a video file
            if (item.type === "video" && item.actualFilePath) {
              // For videos, create file URL with the correct extension
              const fileUrl = `file://${item.actualFilePath}`;
              console.log("Processing video item:", { id: item.id, path: item.actualFilePath, url: fileUrl, fileExtension: item.fileExtension });
              
              return {
                ...item,
                url: fileUrl,
                createdAt: new Date(item.createdAt)
              };
            }
            
            // For other types, ensure dates are Date objects
            return {
              ...item,
              createdAt: new Date(item.createdAt)
            };
          });
          
          setMediaItems(processedItems);
        } else {
          // When running in browser, start with empty state
          console.log("Browser mode - starting with empty media items array");
          setMediaItems([]);
          toast.warning("Running in browser mode. Media items will not be saved permanently.");
        }
      } catch (error) {
        console.error("Error loading media items:", error);
        toast.error("Failed to load media items");
      }
      setIsLoading(false);
    };

    loadMediaItems();
  }, []);

  const processMedia = useCallback(async (file: File) => {
    const reader = new FileReader();
    reader.onload = async (e) => {
      if (!e.target?.result) {
        setIsUploading(false);
        return;
      }

      try {
        // Determine if it's a video file
        const isVideo = isVideoFile(file);
        const fileExtension = getFileExtension(file);
        console.log(`${isVideo ? 'Video' : 'Image'} file extension:`, fileExtension);
        
        let dimensions;
        try {
          dimensions = await getImageDimensions(file);
        } catch (error) {
          console.error("Error getting dimensions:", error);
          dimensions = isVideo ? { width: 640, height: 360 } : { width: 800, height: 600 };
        }

        const newMediaItem: MediaItem = {
          id: crypto.randomUUID(),
          type: isVideo ? "video" : "image",
          url: e.target?.result as string,
          width: dimensions.width,
          height: dimensions.height,
          createdAt: new Date(),
          isAnalyzing: !isVideo && hasApiKey(), // Only analyze images
          fileExtension: fileExtension
        };
        
        // First add to state to show immediate feedback
        setMediaItems(prevItems => [newMediaItem, ...prevItems]);
        
        if (isElectron) {
          try {
            if (isVideo) {
              // Check if saveVideoFile exists before using it
              if (!window.electron.saveVideoFile) {
                throw new Error('saveVideoFile is not available in this version of Electron. Please update your app.');
              }
            
              console.log(`Saving video to filesystem with extension .${fileExtension}`);
              
              // Read the file as ArrayBuffer to send to Electron
              const fileReader = new FileReader();
              fileReader.onload = async (event) => {
                if (!event.target?.result) {
                  throw new Error('Failed to read video file.');
                }
                
                try {
                  const arrayBuf = event.target.result as ArrayBuffer;
                  const uint8Array = new Uint8Array(arrayBuf);
                  
                  // Send to Electron
                  const saveResult = await window.electron.saveVideoFile({
                    id: newMediaItem.id,
                    buffer: Array.from(uint8Array),
                    extension: fileExtension,
                    metadata: {
                      id: newMediaItem.id,
                      type: "video",
                      width: newMediaItem.width,
                      height: newMediaItem.height,
                      createdAt: newMediaItem.createdAt,
                      fileExtension: fileExtension
                    }
                  });
                  
                  if (saveResult.success && saveResult.path) {
                    console.log("Video saved successfully at:", saveResult.path);
                    
                    // Ensure the path has the correct extension
                    if (!saveResult.path.endsWith(`.${fileExtension}`)) {
                      console.error(`Expected path to end with .${fileExtension}, but got ${saveResult.path}`);
                      
                      // Try to fix the path
                      const correctPath = saveResult.path.replace(/\.[^.]+$/, `.${fileExtension}`);
                      console.log("Attempting to use correct path:", correctPath);
                      
                      // Update item with corrected path
                      const updatedItem = {
                        ...newMediaItem,
                        actualFilePath: correctPath,
                        url: `file://${correctPath}`
                      };
                      
                      console.log("Updated video URL:", updatedItem.url);
                      
                      setMediaItems(prevItems => 
                        prevItems.map(item => item.id === newMediaItem.id ? updatedItem : item)
                      );
                    } else {
                      // Path is correct
                      const updatedItem = {
                        ...newMediaItem,
                        actualFilePath: saveResult.path,
                        url: `file://${saveResult.path}`
                      };
                      
                      setMediaItems(prevItems => 
                        prevItems.map(item => item.id === newMediaItem.id ? updatedItem : item)
                      );
                    }
                    
                    toast.success("Video saved to disk");
                  } else {
                    console.error("Failed to save video:", saveResult.error);
                    toast.error(`Failed to save video: ${saveResult.error || "Unknown error"}`);
                  }
                } catch (innerError) {
                  console.error("Failed to save video to filesystem:", innerError);
                  toast.error("Failed to save video to disk. Make sure you're using the latest version of the app.");
                }
              };
              
              fileReader.onerror = () => {
                console.error("Error reading video file as ArrayBuffer");
                toast.error("Failed to process video file");
              };
              
              fileReader.readAsArrayBuffer(file);
            } else {
              // Regular image saving (unchanged)
              console.log("Saving image to filesystem:", newMediaItem.id);
              const saveResult = await window.electron.saveImage({
                id: newMediaItem.id,
                dataUrl: newMediaItem.url,
                metadata: {
                  id: newMediaItem.id,
                  type: newMediaItem.type,
                  width: newMediaItem.width,
                  height: newMediaItem.height,
                  createdAt: newMediaItem.createdAt,
                  isAnalyzing: newMediaItem.isAnalyzing
                }
              });
              
              if (saveResult.success && saveResult.path) {
                console.log("Image saved successfully at:", saveResult.path);
                
                const updatedItem = {
                  ...newMediaItem,
                  actualFilePath: saveResult.path
                };
                
                setMediaItems(prevItems => 
                  prevItems.map(item => item.id === newMediaItem.id ? updatedItem : item)
                );
                
                toast.success("Image saved to disk");
              } else {
                console.error("Failed to save image:", saveResult.error);
                toast.error(`Failed to save image: ${saveResult.error || "Unknown error"}`);
              }
            }
          } catch (error) {
            console.error(`Failed to save ${isVideo ? 'video' : 'image'} to filesystem:`, error);
            toast.error(`Failed to save ${isVideo ? 'video' : 'image'} to disk`);
          }
        } else {
          toast.info(`Running in browser mode. ${isVideo ? 'Video' : 'Image'} is only stored in memory.`);
        }
        
        // Only analyze images, not videos
        if (!isVideo && hasApiKey()) {
          try {
            const patterns = await analyzeImage(newMediaItem.url);
            
            const itemWithPatterns = {
              ...newMediaItem,
              patterns: patterns.map(p => ({ name: p.pattern, confidence: p.confidence })),
              isAnalyzing: false
            };
            
            setMediaItems(prevItems => {
              const updatedWithPatterns = prevItems.map(item => 
                item.id === newMediaItem.id ? itemWithPatterns : item
              );
              
              if (isElectron) {
                try {
                  window.electron.saveImage({
                    id: itemWithPatterns.id,
                    dataUrl: itemWithPatterns.url,
                    metadata: {
                      ...itemWithPatterns,
                      url: undefined
                    }
                  });
                } catch (error) {
                  console.error("Failed to update metadata after analysis:", error);
                }
              }
              
              return updatedWithPatterns;
            });
          } catch (error) {
            console.error("Failed to analyze image:", error);
            
            const errorMessage = error instanceof Error ? error.message : 'Unknown error occurred';
            setMediaItems(prevItems => {
              const updated = prevItems.map(item => 
                item.id === newMediaItem.id ? { ...item, isAnalyzing: false, error: errorMessage } : item
              );
              
              if (isElectron) {
                try {
                  window.electron.saveImage({
                    id: newMediaItem.id,
                    dataUrl: newMediaItem.url,
                    metadata: {
                      ...newMediaItem,
                      isAnalyzing: false,
                      error: errorMessage,
                      url: undefined
                    }
                  });
                } catch (saveError) {
                  console.error("Failed to update metadata after analysis error:", saveError);
                }
              }
              
              return updated;
            });
            
            toast.error("Failed to analyze image: " + errorMessage);
          }
        }
      } catch (processError) {
        console.error("Error processing media:", processError);
        toast.error("Failed to process media: " + (processError instanceof Error ? processError.message : "Unknown error"));
      } finally {
        setIsUploading(false);
      }
    };
    
    reader.readAsDataURL(file);
  }, [isElectron]);

  const addMedia = useCallback(async (file: File) => {
    setIsUploading(true);
    await processMedia(file);
  }, [processMedia]);

  const addUrlCard = useCallback(async (url: string) => {
    setIsUploading(true);
    try {
      const metadata = await fetchUrlMetadata(url);
      
      const newCard: MediaItem = {
        id: crypto.randomUUID(),
        type: "url",
        url: url,
        width: 400,
        height: 120,
        createdAt: new Date(),
        title: metadata.title || url,
        thumbnailUrl: metadata.thumbnailUrl,
        sourceUrl: url
      };
      
      const updatedItems = [newCard, ...mediaItems];
      setMediaItems(updatedItems);
      
      if (isElectron) {
        try {
          await window.electron.saveUrlCard({
            id: newCard.id,
            metadata: newCard
          });
          toast.success(`URL card saved to disk`);
        } catch (error) {
          console.error("Failed to save URL card:", error);
          toast.error("Failed to save URL card to disk");
        }
      } else {
        toast.info("Running in browser mode. URL card is only stored in memory.");
      }
    } catch (error) {
      console.error("Error adding URL card:", error);
      
      const fallbackCard: MediaItem = {
        id: crypto.randomUUID(),
        type: "url",
        url: url,
        width: 400,
        height: 120,
        createdAt: new Date(),
        title: url,
        sourceUrl: url
      };
      
      const updatedItems = [fallbackCard, ...mediaItems];
      setMediaItems(updatedItems);
      
      if (isElectron) {
        try {
          await window.electron.saveUrlCard({
            id: fallbackCard.id,
            metadata: fallbackCard
          });
        } catch (saveError) {
          console.error("Failed to save fallback URL card:", saveError);
          toast.error("Failed to save URL card to disk");
        }
      }
    } finally {
      setIsUploading(false);
    }
  }, [mediaItems, isElectron]);

  const removeMedia = useCallback(async (id: string) => {
    if (isElectron) {
      try {
        await window.electron.deleteImage(id);
        toast.success("Media deleted from disk");
      } catch (error) {
        console.error("Failed to delete from filesystem:", error);
        toast.error("Failed to delete from disk");
      }
    }
    
    const updatedItems = mediaItems.filter(item => item.id !== id);
    setMediaItems(updatedItems);
  }, [mediaItems, isElectron]);

  return {
    images: mediaItems,
    isUploading,
    isLoading,
    addImage: addMedia,
    addUrlCard,
    removeImage: removeMedia,
  };
}

async function fetchUrlMetadata(url: string): Promise<{ title?: string; thumbnailUrl?: string }> {
  try {
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    const domain = new URL(url).hostname;
    const thumbnailUrl = `https://www.google.com/s2/favicons?domain=${domain}&sz=128`;
    
    return {
      title: domain,
      thumbnailUrl
    };
  } catch (error) {
    console.error("Error fetching URL metadata:", error);
    return {};
  }
}
