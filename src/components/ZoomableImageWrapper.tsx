import React, { useState, useRef, useCallback, useEffect } from 'react';
import { ImageItem } from '@/hooks/useImageStore';
import { ImageRenderer } from '@/components/ImageRenderer';

interface ZoomableImageWrapperProps {
  image: ImageItem;
  className?: string;
  alt?: string;
  controls?: boolean;
  autoPlay?: boolean;
  muted?: boolean;
  currentTime?: number;
  onLoad?: (event: React.SyntheticEvent<HTMLImageElement | HTMLVideoElement>) => void;
  onClose?: () => void;
  onZoomStateChange?: (scale: number, position: { x: number; y: number }) => void;
  disableZoom?: boolean;
}

export const ZoomableImageWrapper: React.FC<ZoomableImageWrapperProps> = ({
  image,
  className,
  alt,
  controls = true,
  autoPlay = false,
  muted = false,
  currentTime,
  onLoad,
  onClose,
  onZoomStateChange,
  disableZoom = false
}) => {
  const [scale, setScale] = useState(1);
  const [position, setPosition] = useState({ x: 0, y: 0 });
  const [isDragging, setIsDragging] = useState(false);
  const [dragStart, setDragStart] = useState({ x: 0, y: 0 });
  const [hasDragged, setHasDragged] = useState(false);
  const [velocity, setVelocity] = useState({ x: 0, y: 0 });
  const [isAnimating, setIsAnimating] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);
  const innerRef = useRef<HTMLDivElement>(null);
  const clickTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const lastMoveTime = useRef<number>(0);
  const lastPosition = useRef({ x: 0, y: 0 });
  const animationRef = useRef<number>();

  // Refs for animation loop (bypass React re-renders during momentum)
  const velRef = useRef({ x: 0, y: 0 });
  const posRef = useRef({ x: 0, y: 0 });
  const cachedBoundsRef = useRef({ width: 0, height: 0 });

  const MIN_SCALE = 1;
  const MAX_SCALE = 4;
  const FRICTION = 0.95;
  const MIN_VELOCITY = 0.5;

  // Constrain position within bounds using cached dimensions
  const constrainPosition = useCallback((x: number, y: number, containerWidth?: number, containerHeight?: number) => {
    const w = containerWidth ?? cachedBoundsRef.current.width;
    const h = containerHeight ?? cachedBoundsRef.current.height;
    if (!w || !h) return { x, y };

    const scaledWidth = w * scale;
    const scaledHeight = h * scale;

    const minVisibleRatio = 0.5;
    const maxOffsetX = (scaledWidth - scaledWidth * minVisibleRatio) / scale;
    const maxOffsetY = (scaledHeight - scaledHeight * minVisibleRatio) / scale;

    return {
      x: Math.max(-maxOffsetX, Math.min(maxOffsetX, x)),
      y: Math.max(-maxOffsetY, Math.min(maxOffsetY, y))
    };
  }, [scale]);

  // Momentum animation — writes directly to DOM, no React state during loop
  const animateMomentum = useCallback(() => {
    velRef.current.x *= FRICTION;
    velRef.current.y *= FRICTION;

    if (Math.abs(velRef.current.x) < MIN_VELOCITY && Math.abs(velRef.current.y) < MIN_VELOCITY) {
      // Sync final position to React state once
      setPosition({ ...posRef.current });
      setVelocity({ x: 0, y: 0 });
      setIsAnimating(false);
      return;
    }

    const newPos = constrainPosition(
      posRef.current.x + velRef.current.x,
      posRef.current.y + velRef.current.y
    );
    posRef.current = newPos;

    // Write directly to DOM — no React re-render
    if (innerRef.current) {
      innerRef.current.style.transform =
        `scale(${scale}) translate(${newPos.x / scale}px, ${newPos.y / scale}px)`;
    }

    animationRef.current = requestAnimationFrame(animateMomentum);
  }, [constrainPosition, scale]);

  // Start momentum animation
  const startMomentum = useCallback((velX: number, velY: number) => {
    if (animationRef.current) {
      cancelAnimationFrame(animationRef.current);
    }
    // Cache container dimensions once before the loop
    if (containerRef.current) {
      const rect = containerRef.current.getBoundingClientRect();
      cachedBoundsRef.current = { width: rect.width, height: rect.height };
    }
    velRef.current = { x: velX, y: velY };
    posRef.current = { ...position };
    setIsAnimating(true);
    animationRef.current = requestAnimationFrame(animateMomentum);
  }, [animateMomentum, position]);

  const handleWheel = useCallback((e: WheelEvent) => {
    // Don't handle zoom if disabled
    if (disableZoom) return;
    
    // Only zoom if Cmd (Meta) or Ctrl is pressed
    if (!e.metaKey && !e.ctrlKey) return;
    
    e.preventDefault();
    
    const delta = e.deltaY > 0 ? -0.1 : 0.1;
    const newScale = Math.max(MIN_SCALE, Math.min(MAX_SCALE, scale + delta));
    
    setScale(newScale);
    
    // If zooming out to 1 or below, reset position to center
    if (newScale <= 1) {
      setPosition({ x: 0, y: 0 });
      onZoomStateChange?.(newScale, { x: 0, y: 0 });
    } else {
      onZoomStateChange?.(newScale, position);
    }
  }, [scale, disableZoom]);

  const handleClick = useCallback((e: React.MouseEvent) => {
    if (hasDragged) return; // Don't handle clicks if user just dragged
    
    e.stopPropagation(); // Prevent event bubbling
    
    // Clear any existing timeout
    if (clickTimeoutRef.current) {
      clearTimeout(clickTimeoutRef.current);
      clickTimeoutRef.current = null;
    }
    
    // Set a timeout for single click
    clickTimeoutRef.current = setTimeout(() => {
      // Single click - close modal directly (let parent handle zoom state in exit animation)
      if (onClose) {
        onClose();
      }
    }, 200); // 200ms delay to wait for potential double click
  }, [hasDragged, onClose, scale, position]);

  const handleDoubleClick = useCallback((e: React.MouseEvent) => {
    e.stopPropagation(); // Prevent event bubbling
    
    // Clear the single click timeout
    if (clickTimeoutRef.current) {
      clearTimeout(clickTimeoutRef.current);
      clickTimeoutRef.current = null;
    }
    
    // Don't handle zoom if disabled
    if (disableZoom) {
      // For disabled zoom, double-click just closes the modal
      if (onClose) {
        onClose();
      }
      return;
    }
    
    if (scale === 1) {
      // Zoom in to 2x
      setScale(2);
      setPosition({ x: 0, y: 0 }); // Keep centered
      onZoomStateChange?.(2, { x: 0, y: 0 });
    } else {
      // Zoom out to fit
      setScale(1);
      setPosition({ x: 0, y: 0 });
      onZoomStateChange?.(1, { x: 0, y: 0 });
    }
  }, [scale, onZoomStateChange, disableZoom, onClose]);

  const handleMouseDown = useCallback((e: React.MouseEvent) => {
    if (disableZoom || scale <= 1) return; // Only allow dragging when zoomed in and zoom is enabled
    
    e.preventDefault();
    
    // Stop any ongoing momentum animation
    if (animationRef.current) {
      cancelAnimationFrame(animationRef.current);
      setIsAnimating(false);
    }
    
    setIsDragging(true);
    setHasDragged(false); // Reset drag flag
    setDragStart({
      x: e.clientX - position.x,
      y: e.clientY - position.y
    });
    
    // Initialize velocity tracking
    lastMoveTime.current = Date.now();
    lastPosition.current = { x: e.clientX, y: e.clientY };
  }, [scale, position, disableZoom]);

  const handleMouseMove = useCallback((e: React.MouseEvent) => {
    if (disableZoom || !isDragging || scale <= 1) return;

    e.preventDefault();
    setHasDragged(true);

    const newX = e.clientX - dragStart.x;
    const newY = e.clientY - dragStart.y;

    // Track velocity for momentum
    const now = Date.now();
    const timeDelta = now - lastMoveTime.current;
    if (timeDelta > 0) {
      const deltaX = e.clientX - lastPosition.current.x;
      const deltaY = e.clientY - lastPosition.current.y;

      const velocityX = (deltaX / timeDelta) * 16;
      const velocityY = (deltaY / timeDelta) * 16;

      setVelocity({ x: velocityX, y: velocityY });
    }

    lastMoveTime.current = now;
    lastPosition.current = { x: e.clientX, y: e.clientY };

    // Use cached bounds for constrain during drag
    if (containerRef.current) {
      const rect = containerRef.current.getBoundingClientRect();
      cachedBoundsRef.current = { width: rect.width, height: rect.height };
    }
    const constrainedPos = constrainPosition(newX, newY);
    setPosition(constrainedPos);
    onZoomStateChange?.(scale, constrainedPos);
  }, [isDragging, dragStart, scale, constrainPosition, disableZoom, onZoomStateChange]);

  const handleMouseUp = useCallback(() => {
    setIsDragging(false);
    
    // Start momentum animation if there's sufficient velocity and zoom is enabled
    if (!disableZoom && scale > 1 && (Math.abs(velocity.x) > MIN_VELOCITY || Math.abs(velocity.y) > MIN_VELOCITY)) {
      startMomentum(velocity.x, velocity.y);
    }
    
    // Reset hasDragged after a short delay to allow click handler to check it
    setTimeout(() => setHasDragged(false), 10);
  }, [scale, velocity, startMomentum, disableZoom]);

  // Add wheel event listener with passive: false
  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    container.addEventListener('wheel', handleWheel, { passive: false });

    return () => {
      container.removeEventListener('wheel', handleWheel);
    };
  }, [handleWheel]);

  // Cleanup animation on unmount
  useEffect(() => {
    return () => {
      if (animationRef.current) {
        cancelAnimationFrame(animationRef.current);
      }
    };
  }, []);

  const transform = `scale(${scale}) translate(${position.x / scale}px, ${position.y / scale}px)`;

  return (
    <div 
      ref={containerRef}
      className="w-full h-full flex items-center justify-center"
      style={{
        overflow: 'visible', // Allow image to grow beyond container
        position: 'relative'
      }}
      onClick={handleClick}
      onDoubleClick={handleDoubleClick}
      onMouseDown={handleMouseDown}
      onMouseMove={handleMouseMove}
      onMouseUp={handleMouseUp}
      onMouseLeave={handleMouseUp}
    >
      <div
        ref={innerRef}
        style={{
          transform,
          transition: (isDragging || isAnimating) ? 'none' : 'transform 0.2s ease-out',
          transformOrigin: 'center center',
          cursor: disableZoom ? 'default' : (scale > 1 ? (isDragging ? 'grabbing' : 'grab') : 'default'),
          userSelect: 'none'
        }}
      >
        <ImageRenderer
          image={image}
          alt={alt}
          className={className}
          controls={controls}
          autoPlay={autoPlay}
          muted={muted}
          currentTime={currentTime}
          onLoad={onLoad}
        />
      </div>
    </div>
  );
};