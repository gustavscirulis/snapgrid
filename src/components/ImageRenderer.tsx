
import React, { useState } from "react";
import { ImageItem } from "@/hooks/useImageStore";

interface ImageRendererProps {
  image: ImageItem;
  className?: string;
  alt?: string;
}

export function ImageRenderer({ image, className, alt }: ImageRendererProps) {
  const [loadError, setLoadError] = useState(false);
  
  // For direct file paths, use the URL directly
  // For base64 or web URLs, use them as is
  const imageUrl = image.url;
  
  const handleError = () => {
    console.error(`Failed to load image: ${imageUrl}`);
    setLoadError(true);
  };
  
  if (loadError) {
    return (
      <div className={`bg-gray-200 flex items-center justify-center ${className}`}>
        <span className="text-gray-500">Image failed to load</span>
      </div>
    );
  }
  
  return (
    <img 
      src={imageUrl} 
      alt={alt || `Image ${image.id}`} 
      className={className} 
      onError={handleError}
    />
  );
}
