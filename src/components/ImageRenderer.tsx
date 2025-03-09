import React, { useState } from "react";
import { ImageItem } from "@/hooks/useImageStore";

interface MediaRendererProps {
  image: ImageItem;
  className?: string;
  alt?: string;
  controls?: boolean;
  autoPlay?: boolean;
  muted?: boolean;
  loop?: boolean;
}

export function MediaRenderer({ 
  image, 
  className, 
  alt,
  controls = true,
  autoPlay = false,
  muted = true,
  loop = false
}: MediaRendererProps) {
  const [loadError, setLoadError] = useState(false);

  // For direct file paths, use the URL directly
  // For base64 or web URLs, use them as is
  const mediaUrl = image.url;

  const handleError = (e: React.SyntheticEvent<HTMLImageElement | HTMLVideoElement>) => {
    console.error(`Failed to load media: ${mediaUrl}`, e);
    setLoadError(true);
  };

  if (loadError) {
    return (
      <div className={`bg-gray-200 flex items-center justify-center ${className}`}>
        <span className="text-gray-500">Media failed to load</span>
      </div>
    );
  }

  // Render different elements based on media type
  if (image.type === "video") {
    // For Electron, we need special handling of video files
    console.log('Loading video from URL:', mediaUrl);
    
    return (
      <video 
        src={mediaUrl}
        className={className}
        poster={image.posterUrl}
        controls={controls}
        autoPlay={autoPlay}
        muted={muted}
        loop={loop}
        onError={(e) => {
          console.error('Video error details:', e.currentTarget.error);
          handleError(e);
        }}
        playsInline
        controlsList="nodownload"
      />
    );
  }

  // Default to image rendering
  return (
    <img 
      src={mediaUrl} 
      alt={alt || `Image ${image.id}`} 
      className={className} 
      onError={handleError}
    />
  );
}