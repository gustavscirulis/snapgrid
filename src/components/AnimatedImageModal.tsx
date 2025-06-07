import React, { useEffect, useState, useMemo, useRef, useCallback } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { ImageItem } from "@/hooks/useImageStore";
import { ZoomableImageWrapper } from "@/components/ZoomableImageWrapper";
import { isElectron } from "@/utils/electron";

interface AnimatedImageModalProps {
  isOpen: boolean;
  onClose: () => void;
  selectedImage: ImageItem | null;
  selectedImageRef: React.RefObject<HTMLDivElement> | null;
  patternElements: React.ReactNode | null;
  onAnimationComplete?: (definition: string) => void;
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
  onAnimationComplete,
}) => {
  const [initialPosition, setInitialPosition] = useState<{
    top: number;
    left: number;
    width: number;
    height: number;
  } | null>(null);
  
  // Add a ref to access the video element
  const videoRef = useRef<HTMLVideoElement | null>(null);
  
  // Add state to store actual video dimensions
  const [actualVideoDimensions, setActualVideoDimensions] = useState<{width: number, height: number} | null>(null);

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

  // Handle media load error
  const handleMediaError = useCallback(() => {
    setMediaLoadError(true);
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
  const optimalDimensions = useMemo(() => {
    if (!selectedImage) {
      return null;
    }
    
    // If we have actual video dimensions from the video element, use those instead
    if (selectedImage.type === 'video' && actualVideoDimensions) {
      // Create a copy of the selectedImage with updated dimensions
      const updatedImage = {
        ...selectedImage,
        width: actualVideoDimensions.width,
        height: actualVideoDimensions.height
      };
      
      const dimensions = calculateOptimalDimensions(updatedImage, window.innerWidth, window.innerHeight);
      return dimensions;
    }
    
    const dimensions = calculateOptimalDimensions(selectedImage, window.innerWidth, window.innerHeight);
    return dimensions;
  }, [selectedImage, window.innerWidth, window.innerHeight, actualVideoDimensions]);

  // Calculate fallback dimensions when needed
  useEffect(() => {
    if (selectedImage && initialPosition && !optimalDimensions) {
      const fallback = {
        width: Math.min(800, window.innerWidth * 0.8),
        height: Math.min(600, window.innerHeight * 0.8),
        top: window.innerHeight / 2 - Math.min(600, window.innerHeight * 0.8) / 2,
        left: window.innerWidth / 2 - Math.min(800, window.innerWidth * 0.8) / 2
      };
      setFallbackDimensions(fallback);
    } else {
      setFallbackDimensions(null);
    }
  }, [selectedImage, initialPosition, optimalDimensions]);

  // Get initial position from thumbnail
  useEffect(() => {
    if (isOpen && selectedImageRef?.current) {
      try {
        const rect = selectedImageRef.current.getBoundingClientRect();
        const position = {
          top: rect.top,
          left: rect.left,
          width: rect.width,
          height: rect.height,
        };
        setInitialPosition(position);
      } catch (error) {
        console.error('Error getting initial position:', error);
      }
    } else if (!isOpen) {
      // Ensure we clean up after the exit animation
      setTimeout(() => {
        setInitialPosition(null);
        isAnimatingRef.current = false;
      }, 300);
    }
  }, [isOpen, selectedImageRef]);

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

  // Get video dimensions
  useEffect(() => {
    const getVideoElement = () => {
      const videoElement = document.querySelector('video');
      if (videoElement && selectedImage?.type === 'video') {
        videoRef.current = videoElement;
        
        const updateDimensions = () => {
          const width = videoElement.videoWidth;
          const height = videoElement.videoHeight;
          
          if (width && height) {
            setActualVideoDimensions({ width, height });
          }
        };
        
        if (videoElement.readyState >= 1) {
          updateDimensions();
        } else {
          videoElement.addEventListener('loadedmetadata', updateDimensions);
          return () => videoElement.removeEventListener('loadedmetadata', updateDimensions);
        }
      }
    };
    
    if (isOpen && selectedImage?.type === 'video') {
      getVideoElement();
      const timeoutId = setTimeout(getVideoElement, 500);
      return () => clearTimeout(timeoutId);
    }
  }, [isOpen, selectedImage]);

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
    const containerCenter = window.innerWidth / 2;
    
    // Calculate how to position the element so it appears at the same spot as the thumbnail
    const initialX = initialPosition.left - containerCenter + (initialPosition.width / 2);
    
    // For Y position, we need to adjust for the scrollable container
    const initialY = initialPosition.top;
    
    // Determine if this is a tall image
    const isTallImage = selectedImage && selectedImage.height > selectedImage.width * 2;
    
    // For tall images, keep top alignment with 40px padding
    // For regular images, add moderate top padding (20px)
    const finalY = isTallImage ? 40 : Math.max(20, (window.innerHeight - finalDimensions.height) / 2);
    
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
  }, [initialPosition, optimalDimensions, fallbackDimensions, zoomState]);

  // Log animation variants
  useEffect(() => {}, [modalVariants]);

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
              overflow: 'visible', // Allow zoomed content to extend beyond
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
              animate="open"
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
                onLoad={(e) => {}}
                onClose={handleClose}
                onZoomStateChange={(scale, position) => setZoomState({ scale, position })}
              />
            </motion.div>
          </div>
        </>
      )}
    </AnimatePresence>
  );
};

export default AnimatedImageModal;