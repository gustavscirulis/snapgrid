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
  const mediaRef = useRef<HTMLVideoElement | HTMLImageElement>(null);
  const [hasError, setHasError] = useState(false);
  const [errorMessage, setErrorMessage] = useState('');

  useEffect(() => {
    if (image.type === 'video' && mediaRef.current && 'currentTime' in mediaRef.current && currentTime !== undefined) {
      (mediaRef.current as HTMLVideoElement).currentTime = currentTime;
    }
  }, [currentTime]);

  const handleError = (e: React.SyntheticEvent<HTMLImageElement | HTMLVideoElement>) => {
    setHasError(true);
    const target = e.target as HTMLImageElement | HTMLVideoElement;
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
        ref={mediaRef}
        src={image.url}
        alt={alt}
        className={className}
        controls={controls}
        autoPlay={autoPlay}
        muted={muted}
        onError={handleError}
        onTimeUpdate={() => {
          if (mediaRef.current && 'currentTime' in mediaRef.current && onTimeUpdate) {
            onTimeUpdate((mediaRef.current as HTMLVideoElement).currentTime);
          }
        }}
      />
    );
  }

  return (
    <img
      ref={mediaRef}
      src={image.url}
      alt={alt}
      className={className}
      onError={handleError}
    />
  );
};
