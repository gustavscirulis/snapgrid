
import { useState, useCallback } from "react";

export type ImageItemType = "image" | "url";

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
}

export function useImageStore() {
  const [images, setImages] = useState<ImageItem[]>(() => {
    // Load saved images from localStorage on initialization
    const savedImages = localStorage.getItem("ui-reference-images");
    return savedImages ? JSON.parse(savedImages) : [];
  });
  const [isUploading, setIsUploading] = useState(false);

  // Save to localStorage whenever images change
  const saveToLocalStorage = useCallback((updatedImages: ImageItem[]) => {
    localStorage.setItem("ui-reference-images", JSON.stringify(updatedImages));
  }, []);

  const addImage = useCallback((file: File) => {
    setIsUploading(true);
    
    const reader = new FileReader();
    reader.onload = (e) => {
      const img = new Image();
      img.onload = () => {
        const newImage: ImageItem = {
          id: crypto.randomUUID(),
          type: "image",
          url: e.target?.result as string,
          width: img.width,
          height: img.height,
          createdAt: new Date(),
        };
        
        const updatedImages = [newImage, ...images];
        setImages(updatedImages);
        saveToLocalStorage(updatedImages);
        setIsUploading(false);
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
        height: 300, // Default height for URL cards
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
        height: 300,
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
