import { useState, useCallback, useEffect } from "react";
import { analyzeImage, hasApiKey } from "@/services/aiAnalysisService";
import { toast } from "sonner";
import { getImageDimensions, getVideoDimensions, validateMediaFile } from "@/lib/imageUtils";

export type ImageItemType = "image" | "url" | "video";

export interface PatternTag {
  name: string;
  confidence: number;
}

export interface ImageItem {
  id: string;
  type: ImageItemType;
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
  duration?: number; // Video duration in seconds
  currentTime?: number; // Current playback position
}

export function useImageStore() {
  const [images, setImages] = useState<ImageItem[]>([]);
  const [isUploading, setIsUploading] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [isElectron, setIsElectron] = useState(false);

  useEffect(() => {
    const isRunningInElectron = window && 
      typeof window.electron !== 'undefined' && 
      window.electron !== null;
    
    console.log("useImageStore - Electron detection:", {
      electronExists: typeof window.electron !== 'undefined',
      electronValue: window.electron
    });
    
    setIsElectron(isRunningInElectron);
    
    const loadImages = async () => {
      try {
        if (isRunningInElectron) {
          console.log("Loading images from filesystem...");
          const loadedImages = await window.electron.loadImages();
          console.log("Loaded images:", loadedImages.length);
          setImages(loadedImages);
        } else {
          setImages([]);
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

  const addImage = useCallback(async (file: File) => {
    setIsUploading(true);
    
    const validateResult = validateMediaFile(file);
    if (!validateResult.valid) {
      setIsUploading(false);
      toast.error("Invalid file type or size");
      return;
    }
    
    const fileType = validateResult.type;
    const reader = new FileReader();
    
    reader.onload = async (e) => {
      if (!e.target?.result) {
        setIsUploading(false);
        return;
      }

      let dimensions: { width: number; height: number };
      let duration: number | undefined;
      
      if (fileType === 'image') {
        const img = new Image();
        img.onload = async () => {
          dimensions = { width: img.width, height: img.height };
          processMedia(fileType, e.target?.result as string, dimensions, undefined);
        };
        img.src = e.target?.result as string;
      } else if (fileType === 'video') {
        const video = document.createElement('video');
        video.preload = 'metadata';
        
        video.onloadedmetadata = async () => {
          dimensions = { width: video.videoWidth, height: video.videoHeight };
          duration = video.duration;
          URL.revokeObjectURL(video.src);
          processMedia(fileType, e.target?.result as string, dimensions, duration);
        };
        
        video.src = e.target?.result as string;
      }
    };
    
    reader.readAsDataURL(file);
  }, [images, isElectron]);

  const processMedia = async (type: 'image' | 'video', dataUrl: string, dimensions: { width: number; height: number }, duration?: number) => {
    const newItem: ImageItem = {
      id: crypto.randomUUID(),
      type: type,
      url: dataUrl,
      width: dimensions.width,
      height: dimensions.height,
      createdAt: new Date(),
      isAnalyzing: type === 'image' ? hasApiKey() : false,
      duration: duration
    };
    
    const updatedImages = [newItem, ...images];
    setImages(updatedImages);
    
    if (isElectron) {
      try {
        console.log(`Saving ${type} to filesystem:`, newItem.id);
        const result = await window.electron.saveImage({
          id: newItem.id,
          dataUrl: newItem.url,
          metadata: {
            id: newItem.id,
            type: newItem.type,
            width: newItem.width,
            height: newItem.height,
            createdAt: newItem.createdAt,
            isAnalyzing: newItem.isAnalyzing,
            duration: newItem.duration
          }
        });
        
        if (result.success && result.path) {
          console.log(`${type} saved successfully at:`, result.path);
          newItem.actualFilePath = result.path;
          setImages([newItem, ...images.filter(img => img.id !== newItem.id)]);
          
          toast.success(`${type.charAt(0).toUpperCase() + type.slice(1)} saved to: ${result.path}`);
        } else {
          console.error(`Failed to save ${type}:`, result.error);
          toast.error(`Failed to save ${type}: ${result.error || "Unknown error"}`);
        }
      } catch (error) {
        console.error(`Failed to save ${type} to filesystem:`, error);
        toast.error(`Failed to save ${type} to disk`);
      }
    } else {
      toast.info(`Running in browser mode. ${type.charAt(0).toUpperCase() + type.slice(1)} is only stored in memory.`);
    }
    
    setIsUploading(false);
    
    if (type === 'image' && hasApiKey()) {
      try {
        const patterns = await analyzeImage(newItem.url);
        
        const imageWithPatterns = {
          ...newItem,
          patterns: patterns.map(p => ({ name: p.pattern, confidence: p.confidence })),
          isAnalyzing: false
        };
        
        setImages(prevImages => {
          const updatedWithPatterns = prevImages.map(img => 
            img.id === newItem.id ? imageWithPatterns : img
          );
          
          if (isElectron) {
            try {
              window.electron.saveImage({
                id: imageWithPatterns.id,
                dataUrl: imageWithPatterns.url,
                metadata: {
                  ...imageWithPatterns,
                  url: undefined
                }
              });
            } catch (error) {
              console.error("Failed to update image metadata after analysis:", error);
            }
          }
          
          return updatedWithPatterns;
        });
      } catch (error) {
        console.error("Failed to analyze image:", error);
        
        const errorMessage = error instanceof Error ? error.message : 'Unknown error occurred';
        setImages(prevImages => {
          const updated = prevImages.map(img => 
            img.id === newItem.id ? { ...img, isAnalyzing: false, error: errorMessage } : img
          );
          
          if (isElectron) {
            try {
              window.electron.saveImage({
                id: newItem.id,
                dataUrl: newItem.url,
                metadata: {
                  ...newItem,
                  isAnalyzing: false,
                  error: errorMessage,
                  url: undefined
                }
              });
            } catch (saveError) {
              console.error("Failed to update image metadata after analysis error:", saveError);
            }
          }
          
          return updated;
        });
        
        toast.error("Failed to analyze image: " + errorMessage);
      }
    }
  };

  const addUrlCard = useCallback(async (url: string) => {
    setIsUploading(true);
    try {
      const metadata = await fetchUrlMetadata(url);
      
      const newCard: ImageItem = {
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
      
      const updatedImages = [newCard, ...images];
      setImages(updatedImages);
      
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
      
      const fallbackCard: ImageItem = {
        id: crypto.randomUUID(),
        type: "url",
        url: url,
        width: 400,
        height: 120,
        createdAt: new Date(),
        title: url,
        sourceUrl: url
      };
      
      const updatedImages = [fallbackCard, ...images];
      setImages(updatedImages);
      
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
  }, [images, isElectron]);

  const removeImage = useCallback(async (id: string) => {
    if (isElectron) {
      try {
        await window.electron.deleteImage(id);
        toast.success("Image deleted from disk");
      } catch (error) {
        console.error("Failed to delete image from filesystem:", error);
        toast.error("Failed to delete image from disk");
      }
    }
    
    const updatedImages = images.filter(img => img.id !== id);
    setImages(updatedImages);
  }, [images, isElectron]);

  return {
    images,
    isUploading,
    isLoading,
    addImage,
    addUrlCard,
    removeImage,
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
