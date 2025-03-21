import React, { useEffect, useState, useMemo, useRef, useCallback } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { ImageItem } from "@/hooks/useImageStore";
import { ImageRenderer } from "@/components/ImageRenderer";
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
  // For videos, use maximum screen space while respecting original dimensions
  if (image.type === 'video') {
    // Calculate maximum available space (95% of screen)
    const maxWidth = screenWidth * 0.95;
    const maxHeight = screenHeight * 0.95;
    
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
  
  // For images, use existing logic
  return {
    width: Math.min(image.width || 800, screenWidth * 0.98),
    height: Math.min(image.height || 600, screenHeight * 0.95),
    top: screenHeight / 2 - Math.min(image.height || 600, screenHeight * 0.95) / 2,
    left: screenWidth / 2 - Math.min(image.width || 800, screenWidth * 0.98) / 2
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

  // Add a new state to track media loading errors
  const [mediaLoadError, setMediaLoadError] = useState(false);

  // Add state for fallback dimensions
  const [fallbackDimensions, setFallbackDimensions] = useState<{
    width: number;
    height: number;
    top: number;
    left: number;
  } | null>(null);

  // Handle media load error
  const handleMediaError = useCallback(() => {
    setMediaLoadError(true);
  }, []);

  // Reset error state when modal closes or image changes
  useEffect(() => {
    if (!isOpen) {
      setMediaLoadError(false);
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
        setInitialPosition({
          top: rect.top,
          left: rect.left,
          width: rect.width,
          height: rect.height,
        });
      } catch (error) {
        console.error('Error getting initial position:', error);
        // Only use fallback if we really can't get the position
        const fallback = {
          top: window.innerHeight / 2 - 150,
          left: window.innerWidth / 2 - 200,
          width: 400,
          height: 300,
        };
        setInitialPosition(fallback);
      }
    } else if (!isOpen) {
      setTimeout(() => setInitialPosition(null), 300);
    }
  }, [isOpen, selectedImageRef]);

  // Log optimal dimensions
  useEffect(() => {}, [optimalDimensions]);

  // Handle body overflow and keyboard events
  useEffect(() => {
    if (isOpen) {
      document.body.style.overflow = "hidden";
    } else {
      document.body.style.overflow = "";
    }

    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape" && isOpen) {
        onClose();
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => {
      window.removeEventListener("keydown", handleKeyDown);
      document.body.style.overflow = "";
    };
  }, [isOpen, onClose]);

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

  // Create modal variants
  const modalVariants = useMemo(() => {
    if (!initialPosition) {
      return null;
    }

    const finalDimensions = optimalDimensions || fallbackDimensions;
    if (!finalDimensions) {
      return null;
    }

    const variants = {
      initial: {
        top: initialPosition.top,
        left: initialPosition.left,
        width: initialPosition.width,
        height: initialPosition.height,
        borderRadius: "0.5rem",
        zIndex: 50
      },
      open: {
        top: finalDimensions.top,
        left: finalDimensions.left,
        width: finalDimensions.width,
        height: finalDimensions.height,
        borderRadius: "1rem",
        transition: {
          type: "spring",
          damping: 30,
          stiffness: 300
        }
      },
      exit: {
        top: initialPosition.top,
        left: initialPosition.left,
        width: initialPosition.width,
        height: initialPosition.height,
        borderRadius: "0.5rem",
        transition: {
          type: "spring",
          damping: 30,
          stiffness: 300
        }
      }
    };

    return variants;
  }, [initialPosition, optimalDimensions, fallbackDimensions]);

  // Log animation variants
  useEffect(() => {}, [modalVariants]);

  // Check render conditions
  if (!selectedImage || !initialPosition || !modalVariants) {
    return null;
  }

  return (
    <AnimatePresence onExitComplete={() => onAnimationComplete && onAnimationComplete("exit-complete")}>
      {isOpen && (
        <>
          {/* Backdrop */}
          <motion.div
            className="fixed inset-0 bg-black/80 z-50"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={onClose}
          />

          {/* Image container */}
          <motion.div
            className="fixed z-50 overflow-hidden rounded-lg flex items-center justify-center"
            style={{ position: "fixed" }}
            variants={modalVariants}
            initial="initial"
            animate="open"
            exit="exit"
            onClick={onClose}
            onAnimationComplete={(definition) => {
              if (definition === "exit") {
                onAnimationComplete && onAnimationComplete("exit");
              }
            }}
          >
            <ImageRenderer
              image={selectedImage}
              alt={selectedImage.title || "Selected media"}
              className={`h-full w-auto max-w-full object-contain rounded-xl shadow-xl ${selectedImage.type === 'video' ? 'w-auto max-w-full' : 'mx-auto'}`}
              controls={true}
              autoPlay={selectedImage.type === "video"}
              muted={false}
            />
          </motion.div>
        </>
      )}
    </AnimatePresence>
  );
};

export default AnimatedImageModal;