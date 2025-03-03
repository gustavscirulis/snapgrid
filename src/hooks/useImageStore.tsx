
import { useState, useCallback } from "react";

export interface ImageItem {
  id: string;
  url: string;
  width: number;
  height: number;
  createdAt: Date;
}

export function useImageStore() {
  const [images, setImages] = useState<ImageItem[]>([]);
  const [isUploading, setIsUploading] = useState(false);

  const addImage = useCallback((file: File) => {
    setIsUploading(true);
    
    const reader = new FileReader();
    reader.onload = (e) => {
      const img = new Image();
      img.onload = () => {
        const newImage: ImageItem = {
          id: crypto.randomUUID(),
          url: e.target?.result as string,
          width: img.width,
          height: img.height,
          createdAt: new Date(),
        };
        
        setImages(prev => [newImage, ...prev]);
        setIsUploading(false);
      };
      img.src = e.target?.result as string;
    };
    
    reader.readAsDataURL(file);
  }, []);

  const removeImage = useCallback((id: string) => {
    setImages(prev => prev.filter(img => img.id !== id));
  }, []);

  return {
    images,
    isUploading,
    addImage,
    removeImage,
  };
}
