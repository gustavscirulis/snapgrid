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

  // Refs that mirror state — used by event handlers attached via addEventListener
  // (which would otherwise close over stale state values)
  const scaleRef = useRef(1);
  const velRef = useRef({ x: 0, y: 0 });
  const posRef = useRef({ x: 0, y: 0 });
  const cachedBoundsRef = useRef({ width: 0, height: 0 });

  // Keep refs in sync with state
  useEffect(() => { scaleRef.current = scale; }, [scale]);
  useEffect(() => { posRef.current = position; }, [position]);

  const MIN_SCALE = 1;
  const MAX_SCALE = 4;
  const FRICTION = 0.95;
  const MIN_VELOCITY = 0.5;

  // Constrain position so the zoomed image doesn't pan out of view.
  // With transform model `translate(x,y) scale(s)` and origin center,
  // position values are screen-pixel offsets from the natural centered position.
  const constrainPosition = useCallback((x: number, y: number, currentScale?: number) => {
    const container = containerRef.current;
    if (!container) return { x, y };

    const rect = container.getBoundingClientRect();
    const s = currentScale ?? scaleRef.current;

    // Max offset = how far the image edge can travel from center before
    // the opposite edge passes the container center (at least half visible)
    const maxX = Math.max(0, (rect.width * s - rect.width) / 2);
    const maxY = Math.max(0, (rect.height * s - rect.height) / 2);

    return {
      x: Math.max(-maxX, Math.min(maxX, x)),
      y: Math.max(-maxY, Math.min(maxY, y))
    };
  }, []);

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
        `translate(${newPos.x}px, ${newPos.y}px) scale(${scaleRef.current})`;
    }

    animationRef.current = requestAnimationFrame(animateMomentum);
  }, [constrainPosition]);

  // Start momentum animation
  const startMomentum = useCallback((velX: number, velY: number) => {
    if (animationRef.current) {
      cancelAnimationFrame(animationRef.current);
    }
    velRef.current = { x: velX, y: velY };
    posRef.current = { ...position };
    setIsAnimating(true);
    animationRef.current = requestAnimationFrame(animateMomentum);
  }, [animateMomentum, position]);

  // Cursor-point zoom: adjusts translate so the image point under the cursor
  // stays pinned as scale changes
  const handleWheel = useCallback((e: WheelEvent) => {
    if (disableZoom) return;
    if (!e.metaKey && !e.ctrlKey) return;
    e.preventDefault();

    // Cancel any active momentum
    if (animationRef.current) {
      cancelAnimationFrame(animationRef.current);
      setIsAnimating(false);
    }

    const container = containerRef.current;
    if (!container) return;

    const rect = container.getBoundingClientRect();
    const oldScale = scaleRef.current;
    const oldPos = posRef.current;

    const delta = e.deltaY > 0 ? -0.1 : 0.1;
    const newScale = Math.max(MIN_SCALE, Math.min(MAX_SCALE, oldScale + delta));

    if (newScale <= 1) {
      setScale(1);
      setPosition({ x: 0, y: 0 });
      posRef.current = { x: 0, y: 0 };
      scaleRef.current = 1;
      onZoomStateChange?.(1, { x: 0, y: 0 });
      return;
    }

    // Cursor position relative to container
    const cx = e.clientX - rect.left;
    const cy = e.clientY - rect.top;

    // Container center (transform origin)
    const centerX = rect.width / 2;
    const centerY = rect.height / 2;

    // Point under cursor in image-centered coordinates (before zoom change)
    const pointX = (cx - centerX - oldPos.x) / oldScale;
    const pointY = (cy - centerY - oldPos.y) / oldScale;

    // New translate to keep that point under cursor after zoom change
    const newX = cx - centerX - pointX * newScale;
    const newY = cy - centerY - pointY * newScale;

    const newPos = { x: newX, y: newY };

    // Update refs immediately for subsequent wheel events in same frame batch
    scaleRef.current = newScale;
    posRef.current = newPos;

    setScale(newScale);
    setPosition(newPos);
    onZoomStateChange?.(newScale, newPos);
  }, [disableZoom, onZoomStateChange]);

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
      // Zoom to 2x centered on the click point
      const container = containerRef.current;
      if (!container) return;
      const rect = container.getBoundingClientRect();
      const cx = e.clientX - rect.left;
      const cy = e.clientY - rect.top;
      const centerX = rect.width / 2;
      const centerY = rect.height / 2;

      const newScale = 2;
      // Point under cursor in image-centered coords at scale 1
      const pointX = cx - centerX;
      const pointY = cy - centerY;

      // Keep that point under cursor at new scale
      const newX = cx - centerX - pointX * newScale;
      const newY = cy - centerY - pointY * newScale;

      setScale(newScale);
      setPosition({ x: newX, y: newY });
      onZoomStateChange?.(newScale, { x: newX, y: newY });
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

    // Stop any ongoing momentum animation and sync DOM position to state
    if (animationRef.current) {
      cancelAnimationFrame(animationRef.current);
      setIsAnimating(false);
      // posRef holds the real position during momentum (written to DOM directly),
      // so sync it to React state before starting the new drag
      setPosition({ ...posRef.current });
    }

    const currentPos = posRef.current;
    setIsDragging(true);
    setHasDragged(false); // Reset drag flag
    setDragStart({
      x: e.clientX - currentPos.x,
      y: e.clientY - currentPos.y
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

  // Reset zoom on window resize (container dimensions change, position becomes stale)
  useEffect(() => {
    const handleResize = () => {
      if (scaleRef.current > 1) {
        setScale(1);
        setPosition({ x: 0, y: 0 });
        onZoomStateChange?.(1, { x: 0, y: 0 });
      }
    };
    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, [onZoomStateChange]);

  // Cleanup animation on unmount
  useEffect(() => {
    return () => {
      if (animationRef.current) {
        cancelAnimationFrame(animationRef.current);
      }
    };
  }, []);

  const transform = `translate(${position.x}px, ${position.y}px) scale(${scale})`;

  return (
    <div
      ref={containerRef}
      className={`w-full ${disableZoom ? '' : 'h-full'} flex ${disableZoom ? 'items-start' : 'items-center'} justify-center`}
      style={{
        overflow: 'visible',
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
          userSelect: 'none',
          width: disableZoom ? '100%' : undefined,
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
