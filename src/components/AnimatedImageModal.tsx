import React, { useEffect, useState } from "react";
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
  onAnimatingChange?: (isAnimating: boolean) => void;
}

const AnimatedImageModal: React.FC<AnimatedImageModalProps> = ({
  isOpen,
  onClose,
  selectedImage,
  selectedImageRef,
  onAnimationComplete,
  onAnimatingChange
}) => {
  const [initialPosition, setInitialPosition] = useState<{
    top: number;
    left: number;
    width: number;
    height: number;
  } | null>(null);

  useEffect(() => {
    if (isOpen && selectedImageRef?.current) {
      const rect = selectedImageRef.current.getBoundingClientRect();
      setInitialPosition({
        top: rect.top,
        left: rect.left,
        width: rect.width,
        height: rect.height,
      });
    } else if (!isOpen) {
      setTimeout(() => setInitialPosition(null), 300);
    }
  }, [isOpen, selectedImageRef]);

  useEffect(() => {
    if (isOpen) {
      document.body.style.overflow = "hidden";
    } else {
      // Add a small delay before allowing scrolling again to match the animation
      const timer = setTimeout(() => {
        document.body.style.overflow = "";
      }, 300); // 300ms is the duration of our exit animation
      return () => clearTimeout(timer);
    }
  }, [isOpen]);

  // Track animation state
  const [isAnimatingOut, setIsAnimatingOut] = useState(false);

  const handleClose = () => {
    setIsAnimatingOut(true);
    // Notify parent component about animation state
    if (onAnimatingChange) onAnimatingChange(true);
    // Delay the actual close to complete the animation
    setTimeout(() => {
      onClose();
      setIsAnimatingOut(false);
      if (onAnimatingChange) onAnimatingChange(false);
    }, 300); // Match this to the exit animation duration
  };

  if (!selectedImage || !initialPosition) return null;

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
      top: window.innerHeight / 2 - Math.min(selectedImage.height || 600, window.innerHeight * 0.95) / 2,
      left: window.innerWidth / 2 - Math.min(selectedImage.width || 800, window.innerWidth * 0.98) / 2,
      width: Math.min(selectedImage.width || 800, window.innerWidth * 0.98),
      height: Math.min(selectedImage.height || 600, window.innerHeight * 0.95),
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
            onClick={handleClose}
          />

          {/* Image container - fixed position applied directly to the element */}
          <motion.div
            className="fixed z-50 overflow-hidden rounded-lg flex items-center justify-center" // Added centering classes
            style={{ position: "fixed" }}
            variants={modalVariants}
            initial="initial"
            animate="open"
            exit="exit"
            onClick={handleClose}
            onAnimationComplete={(definition) => {
              if (definition === "exit") {
                onAnimationComplete && onAnimationComplete("exit");
              }
            }}
          >
            <ImageRenderer
              image={selectedImage}
              alt={selectedImage.title || "Selected media"}
              className={`h-full w-auto max-w-full object-contain rounded-lg shadow-xl ${selectedImage.type === 'video' ? 'w-auto max-w-full' : 'mx-auto'}`}
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