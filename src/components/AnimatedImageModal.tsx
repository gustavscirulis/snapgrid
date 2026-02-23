import React, { useEffect, useState, useMemo, useRef, useCallback } from "react";
import { createPortal } from "react-dom";
import { motion, AnimatePresence } from "framer-motion";
import { ImageItem } from "@/hooks/useImageStore";
import { ZoomableImageWrapper } from "@/components/ZoomableImageWrapper";
import { useDragContext } from "./UploadZone";
import { isElectron } from "@/utils/electron";

interface AnimatedImageModalProps {
  isOpen: boolean;
  onClose: () => void;
  selectedImage: ImageItem | null;
  selectedImageRef: React.RefObject<HTMLDivElement> | null;
  initialRect: { top: number; left: number; width: number; height: number } | null;
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
    // For tall images, fit to width and cap height to viewport.
    // The full image is revealed via scrolling inside the motion div after animation.
    const width = Math.min(originalWidth, maxWidth);
    const naturalHeight = (width / originalWidth) * originalHeight;
    const height = Math.min(naturalHeight, screenHeight - 80);

    return {
      width,
      height,
      top: 40,
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
  initialRect,
  onAnimationComplete,
}) => {
  // Use initialRect directly — measured in the click handler before the thumbnail
  // was hidden, so it's available on the very first render (no delay).
  // NOT gated on isOpen: initialRect must persist during exit animation so
  // AnimatePresence can play the shrink-back transition before unmounting.
  const initialPosition = initialRect;

  // Track whether the opening animation has completed (enables scroll for tall images)
  const [openAnimComplete, setOpenAnimComplete] = useState(false);

  // Ref to the motion div so we can scroll-to-top before exit animation
  const motionDivRef = useRef<HTMLDivElement>(null);

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

  // Drag-to-export from fullscreen (same pattern as ImageGrid)
  const dragContext = useDragContext();
  const justExportDraggedRef = useRef(false);
  const customDragRef = useRef<{
    startX: number;
    startY: number;
    isDragging: boolean;
    nativeDragStarted: boolean;
    previewEl: HTMLDivElement | null;
    cleanupTimer: ReturnType<typeof setTimeout> | null;
  } | null>(null);
  // Stable refs so document-level listeners always see the latest values
  const selectedImageRef2 = useRef(selectedImage);
  selectedImageRef2.current = selectedImage;
  const zoomStateRef = useRef(zoomState);
  zoomStateRef.current = zoomState;
  const setInternalDragActiveRef = useRef(dragContext.setInternalDragActive);
  setInternalDragActiveRef.current = dragContext.setInternalDragActive;

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

  // Handle media load error
  const handleMediaError = useCallback(() => {
    setMediaLoadError(true);
  }, []);

  // Reset state when modal closes or image changes
  useEffect(() => {
    if (!isOpen) {
      setMediaLoadError(false);
      setZoomState({ scale: 1, position: { x: 0, y: 0 } });
      setOpenAnimComplete(false);
    }
  }, [isOpen, selectedImage]);

  // Calculate optimal dimensions.
  // Video dimensions are now pre-measured from the thumbnail <video> element in the
  // click handler, so selectedImage.width/height is accurate from the first render.
  // actualVideoDimensions serves as a late fallback only if the thumbnail hadn't loaded.
  const optimalDimensions = useMemo(() => {
    if (!selectedImage) {
      return null;
    }

    // Use actualVideoDimensions only if selectedImage still has missing/fallback values
    if (selectedImage.type === 'video' && actualVideoDimensions &&
        (!selectedImage.width || !selectedImage.height)) {
      const updatedImage = {
        ...selectedImage,
        width: actualVideoDimensions.width,
        height: actualVideoDimensions.height
      };
      return calculateOptimalDimensions(updatedImage, windowSize.width, windowSize.height);
    }

    return calculateOptimalDimensions(selectedImage, windowSize.width, windowSize.height);
  }, [selectedImage, windowSize.width, windowSize.height, actualVideoDimensions]);

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

  // Reset animation ref after modal closes
  useEffect(() => {
    if (!isOpen) {
      const id = setTimeout(() => {
        isAnimatingRef.current = false;
      }, 300);
      return () => clearTimeout(id);
    }
  }, [isOpen]);

  // Handle close with debounce — skip if an export drag just occurred
  const handleClose = useCallback(() => {
    if (isClosingRef.current) return;
    if (justExportDraggedRef.current) return;
    isClosingRef.current = true;
    // Scroll to top and disable overflow before exit animation
    if (motionDivRef.current) {
      motionDivRef.current.scrollTop = 0;
    }
    setOpenAnimComplete(false);
    onClose();
  }, [onClose]);

  // Drag-to-export: mousedown on the image starts potential drag
  const handleExportMouseDown = useCallback((e: React.MouseEvent) => {
    if (e.button !== 0) return;
    if (zoomStateRef.current.scale > 1) return; // let ZoomableImageWrapper handle zoom-pan
    if ((e.target as HTMLElement).closest('button, input, a, video[controls]')) return;

    customDragRef.current = {
      startX: e.clientX,
      startY: e.clientY,
      isDragging: false,
      nativeDragStarted: false,
      previewEl: null,
      cleanupTimer: null,
    };
  }, []);

  // Document-level mousemove/mouseup for export drag
  useEffect(() => {
    if (!isOpen) return;

    const cleanupDrag = () => {
      const state = customDragRef.current;
      if (!state) return;
      if (state.previewEl) state.previewEl.remove();
      if (state.cleanupTimer) clearTimeout(state.cleanupTimer);
      if (state.isDragging) {
        setInternalDragActiveRef.current(false);
      }
      document.body.style.cursor = '';
      customDragRef.current = null;
    };

    const handleMouseMove = (e: MouseEvent) => {
      const state = customDragRef.current;
      if (!state) return;

      // After native drag handed off to OS, detect completion
      if (state.nativeDragStarted) {
        if (e.buttons === 0) {
          cleanupDrag();
          justExportDraggedRef.current = false;
        }
        return;
      }

      if (!state.isDragging) {
        const dx = e.clientX - state.startX;
        const dy = e.clientY - state.startY;
        if (dx * dx + dy * dy < 25) return; // 5px threshold

        state.isDragging = true;
        justExportDraggedRef.current = true;
        setInternalDragActiveRef.current(true);
        document.body.style.cursor = 'grabbing';

        // Create floating thumbnail preview
        const image = selectedImageRef2.current;
        if (image) {
          const preview = document.createElement('div');
          preview.style.cssText =
            'position:fixed;pointer-events:none;width:96px;border-radius:8px;overflow:hidden;box-shadow:0 8px 24px rgba(0,0,0,0.25);transform:rotate(2deg);z-index:99999;opacity:0.7;';
          const img = document.createElement('img');
          img.src = image.thumbnailUrl || image.posterUrl || image.url || '';
          img.style.cssText = 'width:100%;height:auto;display:block;';
          img.draggable = false;
          preview.appendChild(img);
          document.body.appendChild(preview);
          state.previewEl = preview;
        }
      }

      if (state.previewEl) {
        state.previewEl.style.left = `${e.clientX + 12}px`;
        state.previewEl.style.top = `${e.clientY + 8}px`;
      }

      // Near window edge → trigger native drag for desktop export
      const margin = 20;
      const nearEdge =
        e.clientX < margin ||
        e.clientX > window.innerWidth - margin ||
        e.clientY < margin ||
        e.clientY > window.innerHeight - margin;

      if (nearEdge && state.isDragging && window.electron?.startDrag) {
        const image = selectedImageRef2.current;
        if (!image) return;
        const filePath = image.actualFilePath || image.url?.replace('local-file://', '');
        if (filePath) {
          state.nativeDragStarted = true;
          if (state.previewEl) {
            state.previewEl.remove();
            state.previewEl = null;
          }
          document.body.style.cursor = '';

          const iconUrl = image.thumbnailUrl || image.posterUrl || '';
          const iconPath = iconUrl.replace('local-file://', '');
          const displayName =
            image.title || image.imageContext?.substring(0, 60) || undefined;
          window.electron.startDrag(filePath, iconPath, displayName);

          state.cleanupTimer = setTimeout(() => {
            cleanupDrag();
            justExportDraggedRef.current = false;
          }, 10000);
        }
      }

      if (state.isDragging) {
        e.preventDefault();
      }
    };

    const handleMouseUp = () => {
      const state = customDragRef.current;
      if (!state) return;
      if (state.nativeDragStarted) return;

      if (state.isDragging) {
        // Let justExportDraggedRef stay true briefly to block click-to-close
        setTimeout(() => {
          justExportDraggedRef.current = false;
        }, 300);
      } else {
        justExportDraggedRef.current = false;
      }
      cleanupDrag();
    };

    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);
    return () => {
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
      // Clean up any active drag on unmount
      const state = customDragRef.current;
      if (state) {
        if (state.previewEl) state.previewEl.remove();
        if (state.cleanupTimer) clearTimeout(state.cleanupTimer);
      }
      customDragRef.current = null;
    };
  }, [isOpen]);

  // Handle body overflow and keyboard events
  useEffect(() => {
    if (isOpen) {
      // Always hide body overflow — tall image scrolling is handled inside the motion div
      document.body.style.overflow = "hidden";
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
    if (!isOpen || selectedImage?.type !== 'video') return;

    let listenerCleanup: (() => void) | undefined;

    const setupVideoElement = () => {
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
          listenerCleanup = () => videoElement.removeEventListener('loadedmetadata', updateDimensions);
        }
      }
    };

    setupVideoElement();
    const timeoutId = setTimeout(setupVideoElement, 500);

    return () => {
      clearTimeout(timeoutId);
      listenerCleanup?.();
    };
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

  // Create modal variants — animates width/height (layout) on this isolated overlay surface.
  // FLIP (scale-based) is not viable here because thumbnail uses object-cover (cropped)
  // while modal uses object-contain (full image), so content differs at each size.
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
        // Apply inverse zoom transforms so the exit animation undoes the
        // child's translate(x,y) scale(s) and shrinks back to thumbnail cleanly
        ...(zoomState.scale > 1 ? {
          scale: 1 / zoomState.scale,
          x: initialX - zoomState.position.x / zoomState.scale,
          y: initialY - zoomState.position.y / zoomState.scale,
        } : {}),
        transition: zoomState.scale > 1 ? {
          type: "spring",
          damping: 25,
          stiffness: 200
        } : {
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

  const isTallImage = selectedImage.height > selectedImage.width * 2;

  // Portal to document.body so the modal escapes any parent CSS transforms
  // (e.g. the carousel's translateX) that would break position:fixed
  return createPortal(
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

          {/* Fixed wrapper - scrolling for tall images is handled by the motion div */}
          <div
            className="fixed inset-0 z-50 flex justify-center"
            style={{
              overflow: (zoomState.scale > 1 && openAnimComplete) ? 'visible' : 'hidden',
              paddingTop: 0,
              paddingBottom: isTallImage ? '40px' : '20px'
            }}
            onClick={handleClose}
          >
            {/* Image container with animation */}
            <motion.div
              ref={motionDivRef}
              className="rounded-lg flex justify-center"
              style={{
                position: 'relative',
                alignSelf: 'flex-start',
                marginTop: 0,
                marginBottom: 0,
                paddingBottom: isTallImage ? '30px' : 0,
                height: 'fit-content',
                width: 'fit-content',
                minWidth: initialPosition.width,
                minHeight: initialPosition.height,
                transformOrigin: 'center center',
                overflowY: (zoomState.scale > 1 && openAnimComplete)
                  ? 'visible'
                  : (isTallImage && openAnimComplete ? 'auto' : 'hidden'),
                overflowX: (zoomState.scale > 1 && openAnimComplete) ? 'visible' : 'hidden',
              }}
              variants={modalVariants}
              initial="initial"
              animate="open"
              exit="exit"
              onMouseDown={handleExportMouseDown}
              onClick={(e) => {
                // Don't close modal when clicking on the image content during zoom interactions
                e.stopPropagation();
              }}
              onAnimationComplete={(definition) => {
                if (definition === "open") {
                  isAnimatingRef.current = false;
                  setOpenAnimComplete(true);
                } else if (definition === "exit") {
                  onAnimationComplete && onAnimationComplete("exit");
                  isAnimatingRef.current = false;
                  isClosingRef.current = false;
                }
              }}
            >
              <ZoomableImageWrapper
                image={selectedImage}
                alt={selectedImage.title || "Selected media"}
                className={`w-full ${isTallImage ? '' : 'h-full object-contain'} rounded-xl shadow-xl`}
                controls={true}
                autoPlay={selectedImage.type === "video"}
                muted={false}
                currentTime={videoCurrentTime}
                onLoad={(e) => {}}
                onClose={handleClose}
                onZoomStateChange={(scale, position) => setZoomState({ scale, position })}
                disableZoom={isTallImage}
              />
            </motion.div>
          </div>
        </>
      )}
    </AnimatePresence>,
    document.body
  );
};

export default AnimatedImageModal;
