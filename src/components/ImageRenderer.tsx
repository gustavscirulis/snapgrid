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
    const target = e.target as HTMLVideoElement | HTMLImageElement;
    
    // Log the error for debugging but handle differently based on view mode
    if (target.error) {
      console.log(`Media error details:`, target.error);
    }
    
    // For thumbnail view, log but don't show error state
    if (!controls) {
      // Prevent showing error UI in thumbnail mode
      return;
    }
    
    console.error(`Failed to load media: ${image.url}`, e);
    
    // Only set load error for the full view
    setLoadError(true);
    
    // Try to recover from error in Electron
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
  }, [image.url, mediaUrl, image.type, controls, isElectron]);

  // In non-controls mode (thumbnail), we need to handle hover differently
  useEffect(() => {
    // Only apply hover behavior for thumbnail view (when controls are false)
    if (image.type === 'video' && videoRef.current && !controls) {
      const video = videoRef.current;
      
      // Create a stable reference to the play function
      const playVideo = () => {
        if (video.paused) {
          video.muted = true; // Ensure muted for autoplay
          // Use a flag to track if we're still trying to play this video
          let playAttemptCancelled = false;
          
          // Set a small timeout to avoid race conditions
          setTimeout(() => {
            if (!playAttemptCancelled && isHovered) {
              video.play().catch(err => {
                console.log('Video hover playback failed:', err.message);
              });
            }
          }, 50);
          
          return () => { playAttemptCancelled = true; };
        }
      };
      
      if (isHovered && !autoPlay) {
        const cancelPlay = playVideo();
        return cancelPlay;
      } else if (!isHovered && !autoPlay) {
        video.pause();
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

    // In grid view (no controls), show video with poster but enable hover playback
    if (!controls) {
      return (
        <div className={`relative ${className}`} >
          {image.posterUrl ? (
            <>
              {/* Use video element with poster for thumbnail view */}
              <video 
                ref={videoRef}
                className={`w-full h-auto object-cover ${className}`}
                style={{ minHeight: '120px' }}
                src={mediaUrl}
                poster={image.posterUrl}
                muted
                playsInline
                loop
                onError={handleError}
                preload="metadata"
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
        poster={image.posterUrl || undefined}
        controls={controls}
        autoPlay={autoPlay}
        muted={muted}
        loop={loop}
        onError={handleError}
        playsInline
        controlsList="nodownload"
        onLoadStart={() => console.log("Video loading started")}
        onLoadedMetadata={() => console.log("Video metadata loaded")}
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