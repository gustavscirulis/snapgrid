
import { useState, useCallback, useEffect } from "react";
import { analyzeImage, hasApiKey } from "@/services/aiAnalysisService";
import { toast } from "sonner";

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
  thumbnailUrl?: string;
  sourceUrl?: string;
  patterns?: PatternTag[];
  isAnalyzing?: boolean;
  error?: string;
}

// Check if running in Electron
const isElectron = () => {
  return window.electron !== undefined;
};

export function useImageStore() {
  const [images, setImages] = useState<ImageItem[]>([]);
  const [isUploading, setIsUploading] = useState(false);
  const [isLoading, setIsLoading] = useState(true);

  // Load images on initialization
  useEffect(() => {
    const loadImages = async () => {
      if (isElectron()) {
        // Load from Electron filesystem
        try {
          const loadedImages = await window.electron.loadImages();
          setImages(loadedImages);
        } catch (error) {
          console.error("Error loading images from filesystem:", error);
          toast.error("Failed to load images from disk");
        }
      } else {
        // Load from localStorage as fallback when running in browser
        try {
          const savedImages = localStorage.getItem("ui-reference-images");
          if (savedImages) {
            setImages(JSON.parse(savedImages));
          }
        } catch (error) {
          console.error("Error loading images from localStorage:", error);
        }
      }
      setIsLoading(false);
    };

    loadImages();
  }, []);

  // Save images
  const saveImages = useCallback(async (updatedImages: ImageItem[]) => {
    if (isElectron()) {
      // No need to save all images at once when using filesystem
      // Each image is saved individually when added
    } else {
      // Save to localStorage as fallback when running in browser
      try {
        const limitedImages = updatedImages.slice(0, 20);
        localStorage.setItem("ui-reference-images", JSON.stringify(limitedImages));
      } catch (error) {
        console.error("Error saving to localStorage:", error);
        toast.error("Failed to save images to local storage");
      }
    }
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
        
        // Add image to state right away
        const updatedImages = [newImage, ...images];
        setImages(updatedImages);
        
        // Save image to filesystem if in Electron
        if (isElectron()) {
          try {
            await window.electron.saveImage({
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
          } catch (error) {
            console.error("Failed to save image to filesystem:", error);
            toast.error("Failed to save image to disk");
          }
        } else {
          // Save to localStorage if in browser
          saveImages(updatedImages);
        }
        
        setIsUploading(false);
        
        // Start pattern analysis if API key is set
        if (hasApiKey()) {
          try {
            const patterns = await analyzeImage(newImage.url);
            
            // Update the image with patterns
            const imageWithPatterns = {
              ...newImage,
              patterns: patterns.map(p => ({ name: p.pattern, confidence: p.confidence })),
              isAnalyzing: false
            };
            
            // Update the image in the state
            setImages(prevImages => {
              const updatedWithPatterns = prevImages.map(img => 
                img.id === newImage.id ? imageWithPatterns : img
              );
              
              // Save updated image
              if (isElectron()) {
                window.electron.saveImage({
                  id: imageWithPatterns.id,
                  dataUrl: imageWithPatterns.url,
                  metadata: {
                    ...imageWithPatterns,
                    url: undefined // Don't duplicate image data in metadata
                  }
                });
              } else {
                saveImages(updatedWithPatterns);
              }
              
              return updatedWithPatterns;
            });
          } catch (error) {
            console.error("Failed to analyze image:", error);
            
            // Update to remove analyzing state and set error
            const errorMessage = error instanceof Error ? error.message : 'Unknown error occurred';
            setImages(prevImages => {
              const updated = prevImages.map(img => 
                img.id === newImage.id ? { ...img, isAnalyzing: false, error: errorMessage } : img
              );
              
              if (isElectron()) {
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
              } else {
                saveImages(updated);
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
  }, [images, saveImages]);

  const addUrlCard = useCallback(async (url: string) => {
    setIsUploading(true);
    try {
      const metadata = await fetchUrlMetadata(url);
      
      const newCard: ImageItem = {
        id: crypto.randomUUID(),
        type: "url",
        url: url,
        width: 400, // Default width for URL cards
        height: 120, // Reduced height for URL cards to make them compact
        createdAt: new Date(),
        title: metadata.title || url,
        thumbnailUrl: metadata.thumbnailUrl,
        sourceUrl: url
      };
      
      const updatedImages = [newCard, ...images];
      setImages(updatedImages);
      
      // Save URL card
      if (isElectron()) {
        await window.electron.saveUrlCard({
          id: newCard.id,
          metadata: newCard
        });
      } else {
        saveImages(updatedImages);
      }
    } catch (error) {
      console.error("Error adding URL card:", error);
      
      // Add fallback card if metadata fetching fails
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
      
      if (isElectron()) {
        await window.electron.saveUrlCard({
          id: fallbackCard.id,
          metadata: fallbackCard
        });
      } else {
        saveImages(updatedImages);
      }
    } finally {
      setIsUploading(false);
    }
  }, [images, saveImages]);

  const removeImage = useCallback(async (id: string) => {
    if (isElectron()) {
      try {
        await window.electron.deleteImage(id);
      } catch (error) {
        console.error("Failed to delete image from filesystem:", error);
        toast.error("Failed to delete image from disk");
      }
    }
    
    const updatedImages = images.filter(img => img.id !== id);
    setImages(updatedImages);
    
    if (!isElectron()) {
      saveImages(updatedImages);
    }
  }, [images, saveImages]);

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
    // Use a serverless function or proxy to avoid CORS issues
    // For now, we're using a mock implementation
    // In a real app, you'd want to set up a serverless function to fetch this data
    
    // Simulate API call
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // Generate a placeholder image based on the domain
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
