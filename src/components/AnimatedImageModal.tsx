import React, { useEffect, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { ImageItem } from "@/hooks/useImageStore";
import { MediaRenderer } from "@/components/ImageRenderer";

interface AnimatedImageModalProps {
  isOpen: boolean;
  onClose: () => void;
  selectedImage: ImageItem | null;
  selectedImageRef: React.RefObject<HTMLDivElement> | null;
  patternElements: React.ReactNode | null;
  onAnimationComplete?: (definition: string) => void;
}

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
      // Don't reset position immediately to maintain the animation target
      setTimeout(() => setInitialPosition(null), 300);
    }
  }, [isOpen, selectedImageRef]);

  useEffect(() => {
    // Lock body scroll when modal is open
    if (isOpen) {
      document.body.style.overflow = "hidden";
    } else {
      document.body.style.overflow = "";
    }

    // Escape key handler
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
            onClick={onClose}
          />

          {/* Image container - fixed position applied directly to the element */}
          <motion.div
            className="fixed z-50 overflow-hidden rounded-lg"
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
            <MediaRenderer
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