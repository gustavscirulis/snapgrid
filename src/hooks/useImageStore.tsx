import { useState, useCallback, useEffect } from "react";
import { analyzeImage, hasApiKey } from "@/services/aiAnalysisService";
import { toast } from "sonner";
import { fetchUrlMetadata } from "@/lib/metadataUtils";

export type ImageItemType = "image" | "url";

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
  description?: string;
  thumbnailUrl?: string;
  sourceUrl?: string;
  patterns?: PatternTag[];
  isAnalyzing?: boolean;
  error?: string;
  actualFilePath?: string;
  useDirectPath?: boolean; // Flag to indicate if we're using direct file path
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
    
    const reader = new FileReader();
    reader.onload = async (e) => {
      if (!e.target?.result) {
        setIsUploading(false);
        return;
      }

      const img = new Image();
      img.onload = async () => {
        const newImage: ImageItem = {
          id: crypto.randomUUID(),
          type: "image",
          url: e.target?.result as string,
          width: img.width,
          height: img.height,
          createdAt: new Date(),
          isAnalyzing: hasApiKey(),
        };
        
        const updatedImages = [newImage, ...images];
        setImages(updatedImages);
        
        if (isElectron) {
          try {
            console.log("Saving image to filesystem:", newImage.id);
            const result = await window.electron.saveImage({
              id: newImage.id,
              dataUrl: newImage.url,
              metadata: {
                id: newImage.id,
                type: newImage.type,
                width: newImage.width,
                height: newImage.height,
                createdAt: newImage.createdAt,
                isAnalyzing: newImage.isAnalyzing
              }
            });
            
            if (result.success && result.path) {
              console.log("Image saved successfully at:", result.path);
              // Update with direct file path instead of base64
              newImage.actualFilePath = result.path;
              newImage.url = `local-file://${result.path}`;
              newImage.useDirectPath = true;
              setImages([newImage, ...images.filter(img => img.id !== newImage.id)]);
              
              toast.success(`Image saved to: ${result.path}`);
            } else {
              console.error("Failed to save image:", result.error);
              toast.error(`Failed to save image: ${result.error || "Unknown error"}`);
            }
          } catch (error) {
            console.error("Failed to save image to filesystem:", error);
            toast.error("Failed to save image to disk");
          }
        } else {
          toast.info("Running in browser mode. Image is only stored in memory.");
        }
        
        setIsUploading(false);
        
        if (hasApiKey()) {
          try {
            const patterns = await analyzeImage(newImage.url);
            
            const imageWithPatterns = {
              ...newImage,
              patterns: patterns.map(p => ({ name: p.pattern, confidence: p.confidence })),
              isAnalyzing: false
            };
            
            setImages(prevImages => {
              const updatedWithPatterns = prevImages.map(img => 
                img.id === newImage.id ? imageWithPatterns : img
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
                img.id === newImage.id ? { ...img, isAnalyzing: false, error: errorMessage } : img
              );
              
              if (isElectron) {
                try {
                  window.electron.saveImage({
                    id: newImage.id,
                    dataUrl: newImage.url,
                    metadata: {
                      ...newImage,
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
      img.src = e.target?.result as string;
    };
    
    reader.readAsDataURL(file);
  }, [images, isElectron]);

  const addUrlCard = useCallback(async (url: string) => {
    setIsUploading(true);
    try {
      const initialCard: ImageItem = {
        id: crypto.randomUUID(),
        type: "url",
        url: url,
        width: 400,
        height: 400,
        createdAt: new Date(),
        title: url,
        sourceUrl: url,
        isAnalyzing: true
      };
      
      setImages(prevImages => [initialCard, ...prevImages]);
      
      try {
        const metadata = await fetchUrlMetadata(url);
        
        const updatedCard: ImageItem = {
          ...initialCard,
          isAnalyzing: false,
          title: metadata.title || url,
          description: metadata.description,
          thumbnailUrl: metadata.imageUrl || metadata.faviconUrl
        };
        
        setImages(prevImages => 
          prevImages.map(img => img.id === initialCard.id ? updatedCard : img)
        );
        
        if (isElectron) {
          try {
            await window.electron.saveUrlCard({
              id: updatedCard.id,
              metadata: updatedCard
            });
            toast.success(`URL card saved to disk`);
          } catch (error) {
            console.error("Failed to save URL card:", error);
            toast.error("Failed to save URL card to disk");
          }
        }
      } catch (error) {
        console.error("Error fetching URL metadata:", error);
        
        setImages(prevImages => 
          prevImages.map(img => 
            img.id === initialCard.id 
              ? { ...img, isAnalyzing: false, error: "Failed to fetch metadata" } 
              : img
          )
        );
        
        if (isElectron) {
          try {
            await window.electron.saveUrlCard({
              id: initialCard.id,
              metadata: {
                ...initialCard,
                isAnalyzing: false,
                error: "Failed to fetch metadata"
              }
            });
          } catch (saveError) {
            console.error("Failed to save fallback URL card:", saveError);
            toast.error("Failed to save URL card to disk");
          }
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
