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
    if (!selectedImage) return null;

    // If we have actual video dimensions from the video element, use those instead
    if (selectedImage.type === 'video' && actualVideoDimensions) {
      // Create a copy of the selectedImage with updated dimensions
      const updatedImage = {
        ...selectedImage,
        width: actualVideoDimensions.width,
        height: actualVideoDimensions.height
      };

      return calculateOptimalDimensions(updatedImage, window.innerWidth, window.innerHeight);
    }

    return calculateOptimalDimensions(selectedImage, window.innerWidth, window.innerHeight);
  }, [selectedImage, window.innerWidth, window.innerHeight, actualVideoDimensions]);

  useEffect(() => {
    if (isOpen && selectedImageRef?.current) {
      const rect = selectedImageRef.current.getBoundingClientRect();
      const position = {
        top: rect.top,
        left: rect.left,
        width: rect.width,
        height: rect.height,
      };
      setInitialPosition(position);
    } else if (!isOpen) {
      setInitialPosition(null);
    }
  }, [isOpen, selectedImageRef]);

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

  // Add a new useEffect to get the actual video dimensions once it's loaded
  useEffect(() => {
    // Function to get video element and its dimensions
    const getVideoElement = () => {
      // Look for video element in the DOM
      const videoElement = document.querySelector('video');
      if (videoElement && selectedImage?.type === 'video') {
        videoRef.current = videoElement;

        // Function to update dimensions when metadata is loaded
        const updateDimensions = () => {
          const width = videoElement.videoWidth;
          const height = videoElement.videoHeight;

          if (width && height) {
            setActualVideoDimensions({ width, height });
          }
        };

        // If metadata is already loaded
        if (videoElement.readyState >= 1) {
          updateDimensions();
        } else {
          // Otherwise wait for metadata to load
          videoElement.addEventListener('loadedmetadata', updateDimensions);
          return () => videoElement.removeEventListener('loadedmetadata', updateDimensions);
        }
      }
    };

    // If modal is open, try to get video dimensions
    if (isOpen && selectedImage?.type === 'video') {
      // Initial attempt
      getVideoElement();

      // Try again after a short delay to ensure the video element is in the DOM
      const timeoutId = setTimeout(getVideoElement, 500);
      return () => clearTimeout(timeoutId);
    }
  }, [isOpen, selectedImage]);

  if (!selectedImage || !initialPosition || !optimalDimensions) {
    // If we have selectedImage and initialPosition but no optimalDimensions,
    // we can still render the modal with default dimensions
    if (selectedImage && initialPosition && !optimalDimensions) {
      const fallbackDimensions = {
        width: Math.min(800, window.innerWidth * 0.8),
        height: Math.min(600, window.innerHeight * 0.8),
        top: window.innerHeight / 2 - Math.min(600, window.innerHeight * 0.8) / 2,
        left: window.innerWidth / 2 - Math.min(800, window.innerWidth * 0.8) / 2
      };

      const modalVariants = {
        initial: {
          top: initialPosition.top,
          left: initialPosition.left,
          width: initialPosition.width,
          height: initialPosition.height,
          borderRadius: "0.5rem",
          zIndex: 50
        },
        open: {
          top: fallbackDimensions.top,
          left: fallbackDimensions.left,
          width: fallbackDimensions.width,
          height: fallbackDimensions.height,
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

              {/* Image container - fixed position applied directly to the element */}
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
    }

    return null;
  }

  const modalVariants = {
    initial: {
      top: initialPosition.top,
      left: initialPosition.left,
      width: initialPosition.width,
      height: initialPosition.height,
      borderRadius: "0.5rem",
      zIndex: 50
    },
    open: {
      top: optimalDimensions.top,
      left: optimalDimensions.left,
      width: optimalDimensions.width,
      height: optimalDimensions.height,
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

          {/* Image container - fixed position applied directly to the element */}
          <motion.div
            className="fixed z-50 overflow-hidden rounded-lg"
            style={{ 
              position: "fixed",
              top: initialPosition?.top || 0,
              left: initialPosition?.left || 0,
              width: initialPosition?.width || 0,
              height: initialPosition?.height || 0,
              transformOrigin: "top left"
            }}
            initial={{ opacity: 1 }}
            animate={{
              top: optimalDimensions?.top || 0,
              left: optimalDimensions?.left || 0,
              width: optimalDimensions?.width || "100%",
              height: optimalDimensions?.height || "100%",
              opacity: 1
            }}
            exit={{
              top: initialPosition?.top || 0,
              left: initialPosition?.left || 0,
              width: initialPosition?.width || 0,
              height: initialPosition?.height || 0,
              opacity: 0
            }}
            transition={{ duration: 0.3 }}
            transition={{
              duration: 0.3,
              ease: "easeInOut"
            }}
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

            {/* Close button */}
            <button 
              className="absolute top-4 right-4 bg-black/50 text-white rounded-full p-2 hover:bg-black/70 transition-colors"
              onClick={onClose}
            >
              <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <line x1="18" y1="6" x2="6" y2="18"></line>
                <line x1="6" y1="6" x2="18" y2="18"></line>
              </svg>
              <span className="sr-only">Close</span>
            </button>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  );
};

export default AnimatedImageModal;