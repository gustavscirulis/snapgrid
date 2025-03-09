
import React, { useState, useEffect, useRef } from 'react';
import { ImageItem } from '@/hooks/useImageStore';

interface MediaRendererProps {
  image: ImageItem;
  alt: string;
  className?: string;
  controls?: boolean;
  autoPlay?: boolean;
  muted?: boolean;
  isHovered?: boolean;
  currentTime?: number;
  onTimeUpdate?: (time: number) => void;
}

export const ImageRenderer: React.FC<MediaRendererProps> = ({
  image,
  alt,
  className = '',
  controls = false,
  autoPlay = false,
  muted = true,
  isHovered = false,
  currentTime,
  onTimeUpdate,
}) => {
  // Create separate refs for video and image elements
  const videoRef = useRef<HTMLVideoElement>(null);
  const imageRef = useRef<HTMLImageElement>(null);
  const [hasError, setHasError] = useState(false);
  const [errorMessage, setErrorMessage] = useState('');

  useEffect(() => {
    if (image.type === 'video' && videoRef.current && currentTime !== undefined) {
      videoRef.current.currentTime = currentTime;
    }
  }, [currentTime]);

  const handleError = (e: React.SyntheticEvent<HTMLImageElement | HTMLVideoElement>) => {
    setHasError(true);
    const target = e.target as HTMLImageElement | HTMLVideoElement;
    // Check if the target is a video element which has the error property
    if ('error' in target && target.error) {
      setErrorMessage(`Media error: ${target.error.message || 'Unknown error'}`);
      console.error('Media error details:', target.error);
    } else {
      setErrorMessage('Failed to load media');
    }
  };

  if (hasError) {
    return (
      <div className="text-red-500">
        Error loading media: {errorMessage}
      </div>
    );
  }

  if (image.type === 'video') {
    return (
      <video
        ref={videoRef}
        src={image.url}
        alt={alt}
        className={className}
        controls={controls}
        autoPlay={autoPlay}
        muted={muted}
        onError={handleError}
        onTimeUpdate={() => {
          if (videoRef.current && onTimeUpdate) {
            onTimeUpdate(videoRef.current.currentTime);
          }
        }}
      />
    );
  }

  return (
    <img
      ref={imageRef}
      src={image.url}
      alt={alt}
      className={className}
      onError={handleError}
    />
  );
};
