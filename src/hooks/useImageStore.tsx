
import { useState, useCallback } from "react";
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

// Maximum size for the localStorage storage in bytes (approximately 2MB)
const MAX_STORAGE_SIZE = 2 * 1024 * 1024;

// Maximum number of images to store
const MAX_IMAGES = 10;

// Compress image to a smaller size for localStorage
const compressImage = async (dataUrl: string, maxWidth = 600): Promise<string> => {
  return new Promise((resolve) => {
    const img = new Image();
    img.onload = () => {
      const canvas = document.createElement('canvas');
      
      // Calculate new dimensions while maintaining aspect ratio
      let width = img.width;
      let height = img.height;
      
      if (width > maxWidth) {
        const ratio = maxWidth / width;
        width = maxWidth;
        height = height * ratio;
      }
      
      canvas.width = width;
      canvas.height = height;
      
      const ctx = canvas.getContext('2d');
      ctx?.drawImage(img, 0, 0, width, height);
      
      // Compress with reduced quality
      resolve(canvas.toDataURL('image/jpeg', 0.6));
    };
    img.src = dataUrl;
  });
};

export function useImageStore() {
  const [images, setImages] = useState<ImageItem[]>(() => {
    // Load saved images from localStorage on initialization
    try {
      const savedImages = localStorage.getItem("ui-reference-images");
      return savedImages ? JSON.parse(savedImages) : [];
    } catch (error) {
      console.error("Error loading images from localStorage:", error);
      return [];
    }
  });
  const [isUploading, setIsUploading] = useState(false);

  // Save to localStorage with error handling and compression
  const saveToLocalStorage = useCallback(async (updatedImages: ImageItem[]) => {
    try {
      // Limit the number of stored images more aggressively
      const limitedImages = updatedImages.slice(0, MAX_IMAGES);
      
      // Create a copy since we'll be modifying the URLs
      const storedImages = JSON.parse(JSON.stringify(limitedImages));
      
      // Compress image URLs for localStorage
      for (let i = 0; i < storedImages.length; i++) {
        if (storedImages[i].type === "image" && storedImages[i].url.startsWith('data:image')) {
          // Only compress actual data URLs, not thumbnail URLs
          storedImages[i].url = await compressImage(storedImages[i].url);
        }
      }
      
      const serializedData = JSON.stringify(storedImages);
      
      // Check if the data size exceeds the maximum size
      if (serializedData.length > MAX_STORAGE_SIZE) {
        console.warn("Data exceeds localStorage limit, reducing number of stored images");
        // If it's still too big, reduce the number of images further
        storedImages.length = Math.floor(storedImages.length * 0.7); // Remove 30% of images
        localStorage.setItem("ui-reference-images", JSON.stringify(storedImages));
      } else {
        localStorage.setItem("ui-reference-images", serializedData);
      }
    } catch (error) {
      console.error("Error saving to localStorage:", error);
      // Show a toast notification when storage fails
      toast.error("Failed to save images to local storage due to quota limits. Images will be lost on refresh.", {
        duration: 6000,
      });
    }
  }, []);

  const addImage = useCallback(async (file: File) => {
    setIsUploading(true);
    
    const reader = new FileReader();
    reader.onload = async (e) => {
      const img = new Image();
      img.onload = async () => {
        const newImage: ImageItem = {
          id: crypto.randomUUID(),
          type: "image",
          url: e.target?.result as string, // Original URL for display
          width: img.width,
          height: img.height,
          createdAt: new Date(),
          isAnalyzing: hasApiKey(),
        };
        
        // Add image right away
        const updatedImages = [newImage, ...images];
        setImages(updatedImages);
        saveToLocalStorage(updatedImages);
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
              saveToLocalStorage(updatedWithPatterns);
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
              saveToLocalStorage(updated);
              return updated;
            });
            
            toast.error("Failed to analyze image: " + errorMessage);
          }
        }
      };
      img.src = e.target?.result as string;
    };
    
    reader.readAsDataURL(file);
  }, [images, saveToLocalStorage]);

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
      saveToLocalStorage(updatedImages);
    } catch (error) {
      console.error("Error adding URL card:", error);
      // Add fallback card if metadata fetching fails
      const fallbackCard: ImageItem = {
        id: crypto.randomUUID(),
        type: "url",
        url: url,
        width: 400,
        height: 120, // Reduced height for URL cards to make them compact
        createdAt: new Date(),
        title: url,
        sourceUrl: url
      };
      
      const updatedImages = [fallbackCard, ...images];
      setImages(updatedImages);
      saveToLocalStorage(updatedImages);
    } finally {
      setIsUploading(false);
    }
  }, [images, saveToLocalStorage]);

  const removeImage = useCallback((id: string) => {
    const updatedImages = images.filter(img => img.id !== id);
    setImages(updatedImages);
    saveToLocalStorage(updatedImages);
  }, [images, saveToLocalStorage]);

  return {
    images,
    isUploading,
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
