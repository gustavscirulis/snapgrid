import React, { useState, useRef, useEffect, useCallback } from "react";
import { ImageItem } from "@/hooks/useImageStore";
import { isElectron } from "@/utils/electron";

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

  // Get the media URL (handle both direct, local-file and blob URLs)
  let mediaUrl = image.url;

  // If we're in browser mode and using local-file protocol, create a fallback
  const isLocalFileProtocol = mediaUrl && mediaUrl.startsWith('local-file://');

  // In browser development mode, we can't use local-file:// protocol
  if (isLocalFileProtocol && !isElectron) {
    // Use a placeholder or fallback for browser development
    console.log('Using fallback for local file in browser mode');
    mediaUrl = '/placeholder.svg'; // Use a placeholder image from public folder
  }

  const handleError = useCallback((e: React.SyntheticEvent<HTMLVideoElement | HTMLImageElement>) => {
    // Suppress error logging for thumbnail view since we're now using poster images only
    if (!controls) return;
    
    const target = e.target as HTMLVideoElement | HTMLImageElement;
    if (target.error) {
      console.error(`Media error details:`, target.error);
    }
    console.error(`Failed to load media: ${image.url}`, e);
    
    setLoadError(true);
    
    // Only attempt URL fixes in Electron environment with full controls
    if (mediaUrl.startsWith('local-file://') && image.type === 'video' && controls && isElectron) {
      const fixedSrc = mediaUrl.replace('local-file://', 'file://');
      console.log("Attempting with corrected URL:", fixedSrc);
      if (videoRef.current){
        videoRef.current.src = fixedSrc;
      }
    }
  }, [image.url, mediaUrl, image.type, controls]);

  useEffect(() => {
    if (image.type === 'video' && videoRef.current && controls) {
      if (isHovered && !autoPlay) {
        videoRef.current.play().catch(err => console.error('Video play error:', err));
      } else if (!isHovered && !autoPlay) {
        videoRef.current.pause();
      }
    }
  }, [isHovered, autoPlay, image.type, controls]);

  if (loadError) {
    return (
      <div className={`bg-gray-200 flex items-center justify-center ${className}`}>
        <span className="text-gray-500">Media failed to load</span>
      </div>
    );
  }

  // Render different elements based on media type
  if (image.type === "video") {
    console.log('Loading video from URL:', mediaUrl); 

    // In grid view (no controls), show the poster image as a thumbnail
    if (!controls) {
      return (
        <div className={`relative ${className}`} >
          {image.posterUrl ? (
            <>
              {/* Always use the poster image in thumbnail view to avoid video loading errors */}
              <div 
                className={`w-full h-auto object-cover ${className}`}
                style={{
                  backgroundImage: `url(${image.posterUrl})`,
                  backgroundSize: 'cover',
                  backgroundPosition: 'center',
                  minHeight: '120px'
                }}
                onMouseEnter={() => setIsHovered(true)}
                onMouseLeave={() => setIsHovered(false)}
              />
            </>
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
        onError={handleError}
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