import React, { useEffect, useState, useMemo, useRef, useCallback } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { ImageItem } from "@/hooks/useImageStore";
import { ZoomableImageWrapper } from "@/components/ZoomableImageWrapper";

interface AnimatedImageModalProps {
  isOpen: boolean;
  onClose: () => void;
  selectedImage: ImageItem | null;
  selectedImageRef: React.RefObject<HTMLDivElement> | null;
  initialPosition?: { top: number; left: number; width: number; height: number } | null;
  patternElements: React.ReactNode | null;
  onAnimationComplete?: (definition: string) => void;
  onModalImageReady?: () => void;
}

// Function to calculate optimal dimensions
const calculateOptimalDimensions = (image: ImageItem, screenWidth: number, screenHeight: number) => {
  // Account for padding in available height
  const verticalPadding = 40; // 20px top + 20px bottom
  const availableHeight = screenHeight - verticalPadding;
  
  // For videos, use maximum screen space while respecting original dimensions
  if (image.type === 'video') {
    // Calculate maximum available space (95% of screen)
    const maxWidth = screenWidth * 0.95;
    const maxHeight = availableHeight * 0.95;
    
    // Get original dimensions, with fallbacks
    const originalWidth = image.width || 800;
    const originalHeight = image.height || 600;
    
    // Calculate scaling factors to fit within screen
    const widthScale = maxWidth / originalWidth;
    const heightScale = maxHeight / originalHeight;
    
    // Use the smaller scaling factor to ensure both dimensions fit
    // If scale > 1, it means we can fit the video at larger than original size,
    // but we'll cap at 1 to avoid quality loss
    const scale = Math.min(widthScale, heightScale);
    
    // Calculate final dimensions - never exceed original dimensions
    const width = originalWidth * Math.min(scale, 1);
    const height = originalHeight * Math.min(scale, 1);
    
    return {
      width,
      height,
      top: (screenHeight - height) / 2,
      left: (screenWidth - width) / 2
    };
  }
  
  // For images, ensure we never exceed original dimensions
  const originalWidth = image.width || 800;
  const originalHeight = image.height || 600;
  
  // Calculate maximum available space (95% of screen)
  const maxWidth = screenWidth * 0.95;
  const maxHeight = availableHeight * 0.95;
  
  // Check if image is tall (height > 2x width)
  const isTallImage = originalHeight > originalWidth * 2;
  
  if (isTallImage) {
    // For tall images, fit to width and top-align
    const width = Math.min(originalWidth, maxWidth);
    const height = (width / originalWidth) * originalHeight;
    
    return {
      width,
      height,
      top: 40, // Fixed padding that's consistent with the design
      left: (screenWidth - width) / 2
    };
  }
  
  // For regular images, use the smaller scaling factor to ensure both dimensions fit
  const widthScale = maxWidth / originalWidth;
  const heightScale = maxHeight / originalHeight;
  const scale = Math.min(widthScale, heightScale);
  
  // Calculate final dimensions - never exceed original dimensions
  const width = originalWidth * Math.min(scale, 1);
  const height = originalHeight * Math.min(scale, 1);
  
  return {
    width,
    height,
    top: (screenHeight - height) / 2,
    left: (screenWidth - width) / 2
  };
};

const AnimatedImageModal: React.FC<AnimatedImageModalProps> = ({
  isOpen,
  onClose,
  selectedImage,
  selectedImageRef,
  initialPosition: initialPositionProp,
  onAnimationComplete,
  onModalImageReady,
}) => {
  // Use the synchronously-captured position from the click handler directly.
  // This eliminates the 1-2 frame gap where the thumbnail is hidden but the modal hasn't rendered.
  const initialPosition = initialPositionProp ?? null;

  // Track whether the modal's image content has loaded.
  // The spring animation is held at "initial" (thumbnail position) until the image
  // is ready, preventing a blank/empty div from animating across the screen.
  const [imageLoaded, setImageLoaded] = useState(false);

  // Reset when a new image is selected
  useEffect(() => {
    setImageLoaded(false);
  }, [selectedImage?.id]);

  // Safety fallback: start animation after 400ms even if image hasn't loaded
  useEffect(() => {
    if (isOpen && !imageLoaded) {
      const timeout = setTimeout(() => setImageLoaded(true), 400);
      return () => clearTimeout(timeout);
    }
  }, [isOpen, imageLoaded]);

  // For videos, preload the poster image so the animation doesn't start
  // until there's actual visual content to show. The <video> element's
  // onLoadedMetadata fires when metadata (duration/dimensions) is known,
  // which is long before the poster or first frame is painted.
  useEffect(() => {
    if (isOpen && selectedImage?.type === 'video' && selectedImage.posterUrl) {
      const img = new window.Image();
      img.onload = async () => {
        try { await img.decode(); } catch {}
        setImageLoaded(true);
        onModalImageReady?.();
      };
      img.src = selectedImage.posterUrl;
      return () => { img.onload = null; };
    }
  }, [isOpen, selectedImage?.id]); // eslint-disable-line react-hooks/exhaustive-deps

  const handleImageLoaded = useCallback(() => {
    // For videos with posters, imageLoaded is set via the poster-preload
    // effect above — skip the duplicate call from onLoadedMetadata.
    if (selectedImage?.type === 'video' && selectedImage.posterUrl) return;
    setImageLoaded(true);
    onModalImageReady?.();
  }, [onModalImageReady, selectedImage?.type, selectedImage?.posterUrl]);

  // Add state to track media loading errors
  const [mediaLoadError, setMediaLoadError] = useState(false);

  // Add state to track video current time
  const [videoCurrentTime, setVideoCurrentTime] = useState(0);

  // Add state for fallback dimensions
  const [fallbackDimensions, setFallbackDimensions] = useState<{
    width: number;
    height: number;
    top: number;
    left: number;
  } | null>(null);

  // Track zoom state for exit animation
  const [zoomState, setZoomState] = useState({ scale: 1, position: { x: 0, y: 0 } });

  // Add ref to track if we're currently animating
  const isAnimatingRef = useRef(false);

  // Add ref to track if we're currently closing
  const isClosingRef = useRef(false);

  // Track window size reactively so layout recalculates on resize
  const [windowSize, setWindowSize] = useState({
    width: window.innerWidth,
    height: window.innerHeight
  });

  useEffect(() => {
    const handleResize = () => {
      setWindowSize({ width: window.innerWidth, height: window.innerHeight });
    };
    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, []);
  // Reset error state when modal closes or image changes
  useEffect(() => {
    if (!isOpen) {
      setMediaLoadError(false);
      // Reset zoom state when modal closes
      setZoomState({ scale: 1, position: { x: 0, y: 0 } });
    }
  }, [isOpen, selectedImage]);

  // Calculate optimal dimensions using the new function
  // Uses metadata dimensions only — never update mid-animation from the <video> element,
  // as that causes the spring animation target to change and produces a visible bounce.
  const optimalDimensions = useMemo(() => {
    if (!selectedImage) {
      return null;
    }

    return calculateOptimalDimensions(selectedImage, windowSize.width, windowSize.height);
  }, [selectedImage, windowSize.width, windowSize.height]);

  // Calculate fallback dimensions when needed
  useEffect(() => {
    if (selectedImage && initialPosition && !optimalDimensions) {
      const fallback = {
        width: Math.min(800, windowSize.width * 0.8),
        height: Math.min(600, windowSize.height * 0.8),
        top: windowSize.height / 2 - Math.min(600, windowSize.height * 0.8) / 2,
        left: windowSize.width / 2 - Math.min(800, windowSize.width * 0.8) / 2
      };
      setFallbackDimensions(fallback);
    } else {
      setFallbackDimensions(null);
    }
  }, [selectedImage, initialPosition, optimalDimensions, windowSize]);

  // Clean up animation state after modal closes
  useEffect(() => {
    if (!isOpen) {
      const timeout = setTimeout(() => {
        isAnimatingRef.current = false;
      }, 300);
      return () => clearTimeout(timeout);
    }
  }, [isOpen]);

  // Handle close with debounce
  const handleClose = useCallback(() => {
    if (isClosingRef.current) return;
    isClosingRef.current = true;
    onClose();
  }, [onClose]);

  // Handle body overflow and keyboard events
  useEffect(() => {
    if (isOpen) {
      // Allow scrolling for tall images
      if (selectedImage?.height > (selectedImage?.width || 0) * 2) {
        // Tall image - keep scrolling enabled
      } else {
        document.body.style.overflow = "hidden";
      }
      isAnimatingRef.current = true;
      isClosingRef.current = false;
    } else {
      document.body.style.overflow = "";
    }

    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape" && isOpen) {
        handleClose();
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => {
      window.removeEventListener("keydown", handleKeyDown);
      document.body.style.overflow = "";
      isAnimatingRef.current = false;
      isClosingRef.current = false;
    };
  }, [isOpen, selectedImage, handleClose]);

  // Get video current time from thumbnail when modal opens
  useEffect(() => {
    if (isOpen && selectedImage?.type === 'video') {
      const thumbnailVideo = document.querySelector(`video[src="${selectedImage.url}"]`);
      if (thumbnailVideo instanceof HTMLVideoElement) {
        setVideoCurrentTime(thumbnailVideo.currentTime);
      }
    }
  }, [isOpen, selectedImage]);

  // Create modal variants
  const modalVariants = useMemo(() => {
    if (!initialPosition) {
      return null;
    }

    const finalDimensions = optimalDimensions || fallbackDimensions;
    if (!finalDimensions) {
      return null;
    }

    // Calculate the center position for our scrollable flex container
    const containerCenter = windowSize.width / 2;

    // Calculate how to position the element so it appears at the same spot as the thumbnail
    const initialX = initialPosition.left - containerCenter + (initialPosition.width / 2);

    // For Y position, we need to adjust for the scrollable container
    const initialY = initialPosition.top;

    // Determine if this is a tall image
    const isTallImage = selectedImage && selectedImage.height > selectedImage.width * 2;

    // For tall images, keep top alignment with 40px padding
    // For regular images, add moderate top padding (20px)
    const finalY = isTallImage ? 40 : Math.max(20, (windowSize.height - finalDimensions.height) / 2);
    
    // For the position-absolute scrollable layout, we only need width and height
    // The position is handled by the scrollable container
    const variants = {
      initial: {
        width: initialPosition.width,
        height: initialPosition.height,
        x: initialX,
        y: initialY,
        borderRadius: "0.5rem",
        zIndex: 50
      },
      open: {
        width: finalDimensions.width,
        height: finalDimensions.height,
        x: 0,
        y: finalY,
        borderRadius: "1rem",
        transition: {
          type: "spring",
          damping: 30,
          stiffness: 300
        }
      },
      exit: {
        width: initialPosition.width,
        height: initialPosition.height,
        x: initialX,
        y: initialY,
        borderRadius: "0.5rem",
        // Only apply inverse transforms when actually zoomed in
        ...(zoomState.scale > 1 ? {
          scale: 1 / zoomState.scale,
          translateX: -zoomState.position.x / zoomState.scale,
          translateY: -zoomState.position.y / zoomState.scale,
        } : {}),
        transition: zoomState.scale > 1 ? {
          // Slower transition when zoomed in
          type: "spring",
          damping: 25,
          stiffness: 200
        } : {
          // Normal speed when not zoomed
          type: "spring",
          damping: 30,
          stiffness: 300
        }
      }
    };

    return variants;
  }, [initialPosition, optimalDimensions, fallbackDimensions, zoomState, windowSize, selectedImage]);

  // Check render conditions
  if (!selectedImage || !initialPosition || !modalVariants) {
    return null;
  }

  return (
    <AnimatePresence onExitComplete={() => {
      onAnimationComplete && onAnimationComplete("exit");
      isAnimatingRef.current = false;
      isClosingRef.current = false;
    }}>
      {isOpen && (
        <>
          {/* Backdrop */}
          <motion.div
            className="fixed inset-0 bg-black/80 z-40"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={handleClose}
          />

          {/* Scrollable wrapper - fixed position but allows scrolling */}
          <div 
            className="fixed inset-0 z-50 flex justify-center" 
            style={{ 
              overflow: selectedImage.height > selectedImage.width * 2 ? 'auto' : 'visible', // Enable scrolling for tall images
              paddingTop: 0,
              paddingBottom: selectedImage.height > selectedImage.width * 2 ? '40px' : '20px'
            }}
            onClick={handleClose}
          >
            {/* Image container with animation */}
            <motion.div
              className="rounded-lg flex justify-center"
              style={{ 
                position: 'relative',
                alignSelf: 'flex-start',
                marginTop: 0,
                marginBottom: 0,
                paddingBottom: selectedImage.height > selectedImage.width * 2 ? '30px' : 0,
                height: 'fit-content',
                width: 'fit-content',
                minWidth: initialPosition.width,
                minHeight: initialPosition.height,
                transformOrigin: 'center center'
              }}
              variants={modalVariants}
              initial="initial"
              animate={imageLoaded ? "open" : "initial"}
              exit="exit"
              onClick={(e) => {
                // Don't close modal when clicking on the image content during zoom interactions
                e.stopPropagation();
              }}
              onAnimationComplete={(definition) => {
                if (definition === "exit") {
                  onAnimationComplete && onAnimationComplete("exit");
                  isAnimatingRef.current = false;
                  isClosingRef.current = false;
                }
              }}
            >
              <ZoomableImageWrapper
                image={selectedImage}
                alt={selectedImage.title || "Selected media"}
                className={`w-full h-full ${selectedImage.height > selectedImage.width * 2 ? 'object-cover object-top' : 'object-contain'} rounded-xl shadow-xl`}
                controls={true}
                autoPlay={selectedImage.type === "video"}
                muted={false}
                currentTime={videoCurrentTime}
                onLoad={handleImageLoaded}
                onClose={handleClose}
                onZoomStateChange={(scale, position) => setZoomState({ scale, position })}
                disableZoom={selectedImage.height > selectedImage.width * 2}
              />
            </motion.div>
          </div>
        </>
      )}
    </AnimatePresence>
  );
};

export default AnimatedImageModal;