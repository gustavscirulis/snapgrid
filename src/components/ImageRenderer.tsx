import React, { useState, useRef, useCallback } from 'react';
import { ImageItem } from '@/hooks/useImageStore';

interface ImageRendererProps {
  image: ImageItem;
  className?: string;
  alt?: string;
  controls?: boolean;
  autoPlay?: boolean;
  muted?: boolean;
  loop?: boolean;
}

export function ImageRenderer({
  image,
  className = "",
  alt = "",
  controls = false,
  autoPlay = false,
  muted = true,
  loop = false
}: ImageRendererProps) {
  const [loadError, setLoadError] = useState(false);
  const videoRef = useRef<HTMLVideoElement>(null);

  // Determine if we're running in Electron
  const isElectron = window && 
    typeof window.electron !== 'undefined' && 
    window.electron !== null;

  // Process the media URL
  let mediaUrl = image.url;
  const isLocalFileProtocol = mediaUrl.startsWith('local-file://');

  // In browser development mode, we can't use local-file:// protocol for security reasons
  if (isLocalFileProtocol && !isElectron) {
    if (image.type === 'video') {
      console.log('Video in browser mode - will use poster image');
      // We'll rely on the poster image for thumbnails in browser mode
    } else {
      // For images in browser, use a placeholder
      console.log('Using placeholder for local file in browser mode');
      mediaUrl = '/placeholder.svg';
    }
  }

  // Handle media loading errors
  const handleError = useCallback((e: React.SyntheticEvent<HTMLVideoElement | HTMLImageElement>) => {
    const target = e.target as HTMLVideoElement | HTMLImageElement;

    if (target.error) {
      console.log(`Media error details:`, target.error);
    }

    console.error(`Failed to load media: ${image.url}`, e);
    setLoadError(true);

    // Try to recover from error in Electron by using file:// protocol
    if (mediaUrl.startsWith('local-file://') && image.type === 'video' && isElectron) {
      try {
        const fixedSrc = mediaUrl.replace('local-file://', 'file://');
        console.log("Attempting with corrected URL:", fixedSrc);
        if (videoRef.current) {
          videoRef.current.src = fixedSrc;
        }
      } catch (err) {
        console.error("Error applying video URL fix:", err);
      }
    }
  }, [image.url, mediaUrl, image.type, isElectron]);

  // Display error state if media failed to load
  if (loadError) {
    return (
      <div className={`bg-gray-200 flex items-center justify-center ${className}`}>
        <span className="text-gray-500">Media failed to load</span>
      </div>
    );
  }

  // Render video element
  if (image.type === "video") {

    // In thumbnail view (grid)
    if (!controls) {
      return (
        <div className={`relative ${className}`}>
          {image.posterUrl ? (
            // Show poster image in grid view
            <img 
              src={image.posterUrl} 
              alt={`Video thumbnail ${image.id}`}
              className={`w-full h-auto object-cover ${className}`}
              style={{ minHeight: '120px' }}
            />
          ) : (
            // Fallback if no poster is available
            <div className={`flex items-center justify-center bg-gray-200 ${className}`}>
              <span>Video thumbnail not available</span>
            </div>
          )}
          {/* Video indicator icon */}
          <div className="absolute bottom-2 right-2 bg-black/70 p-1 rounded text-white text-xs">
            <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 20 20" xmlns="http://www.w3.org/2000/svg">
              <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM9.555 7.168A1 1 0 008 8v4a1 1 0 001.555.832l3-2a1 1 0 000-1.664l-3-2z" clipRule="evenodd"></path>
            </svg>
          </div>
        </div>
      );
    }

    // In full view (modal with controls)
    return (
      <video 
        ref={videoRef}
        src={mediaUrl}
        className={className}
        poster={image.posterUrl || undefined}
        controls={controls}
        autoPlay={autoPlay}
        muted={muted}
        loop={loop}
        onError={handleError}
        playsInline
        controlsList="nodownload"
        preload="auto"
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