import React, { useState, useRef, useEffect } from "react";
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
  const videoRef = useRef<HTMLVideoElement>(null);
  const [isHovered, setIsHovered] = useState(false);

  // For direct file paths, use the URL directly
  // For base64 or web URLs, use them as is
  const mediaUrl = image.url;

  const handleError = (e: React.SyntheticEvent<HTMLImageElement | HTMLVideoElement>) => {
    console.error(`Failed to load media: ${mediaUrl}`, e);
    setLoadError(true);
  };

  useEffect(() => {
    if (image.type === 'video' && videoRef.current) {
      if (isHovered && !autoPlay) {
        videoRef.current.play().catch(err => console.error('Video play error:', err));
      } else if (!isHovered && !autoPlay) {
        videoRef.current.pause();
      }
    }
  }, [isHovered, autoPlay, image.type]);

  if (loadError) {
    return (
      <div className={`bg-gray-200 flex items-center justify-center ${className}`}>
        <span className="text-gray-500">Media failed to load</span>
      </div>
    );
  }

  // Render different elements based on media type
  if (image.type === "video") {
    console.log('Loading video from URL:', mediaUrl); //Removed "Video poster URL" log

    // In grid view (no controls), show the poster image as a thumbnail
    if (!controls) {
      return (
        <div className={`relative ${className}`} >
          {image.posterUrl ? (
            <video 
              ref={videoRef}
              src={mediaUrl}
              className={`w-full h-auto object-cover ${className}`}
              poster={image.posterUrl}
              muted={true}
              loop={loop}
              onMouseEnter={() => setIsHovered(true)}
              onMouseLeave={() => setIsHovered(false)}
              onError={handleError}
              playsInline
              controlsList="nodownload"
            />
          ) : (
            <div className={`flex items-center justify-center bg-gray-200 ${className}`}>
              <span>Video thumbnail not available</span>
            </div>
          )}
          <div className="absolute bottom-2 right-2 bg-black/70 p-1 rounded text-white text-xs">
            <svg className="w-4 h-4 inline-block mr-1" fill="currentColor" viewBox="0 0 20 20" xmlns="http://www.w3.org/2000/svg">
              <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM9.555 7.168A1 1 0 008 8v4a1 1 0 001.555.832l3-2a1 1 0 000-1.664l-3-2z" clipRule="evenodd"></path>
            </svg>
            {image.duration ? `${Math.floor(image.duration)}s` : 'Video'}
          </div>
        </div>
      );
    }

    // In full view (with controls), show the actual video player
    return (
      <video 
        ref={videoRef}
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