
import React, { useEffect, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { ImageItem, PatternTag } from "@/hooks/useImageStore";
import { X, Scan, AlertCircle } from "lucide-react";

interface AnimatedImageModalProps {
  isOpen: boolean;
  onClose: () => void;
  selectedImage: ImageItem | null;
  selectedImageRef: React.RefObject<HTMLDivElement> | null;
  patternElements: React.ReactNode | null;
}

const AnimatedImageModal: React.FC<AnimatedImageModalProps> = ({
  isOpen,
  onClose,
  selectedImage,
  selectedImageRef,
  patternElements,
}) => {
  const [initialPosition, setInitialPosition] = useState<{
    top: number;
    left: number;
    width: number;
    height: number;
  } | null>(null);
  
  // Add state to control pattern visibility
  const [showPatterns, setShowPatterns] = useState(false);

  useEffect(() => {
    if (isOpen && selectedImageRef?.current) {
      const rect = selectedImageRef.current.getBoundingClientRect();
      setInitialPosition({
        top: rect.top,
        left: rect.left,
        width: rect.width,
        height: rect.height,
      });
      // Show patterns after a short delay when opening
      const timer = setTimeout(() => setShowPatterns(true), 300);
      return () => clearTimeout(timer);
    } else if (!isOpen) {
      // Hide patterns immediately when closing
      setShowPatterns(false);
      // Reset position with delay
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

  const renderPatternTags = (patterns?: PatternTag[], isAnalyzing?: boolean, error?: string) => {
    if (!patterns || patterns.length === 0) {
      if (isAnalyzing) {
        return (
          <div className="flex items-center gap-2 text-sm bg-primary/10 px-3 py-2 rounded-md">
            <Scan className="w-4 h-4 animate-pulse text-primary" />
            <span>Analyzing UI patterns...</span>
          </div>
        );
      }

      if (error) {
        return (
          <div className="flex items-center gap-2 text-sm bg-destructive/10 px-3 py-2 rounded-md">
            <AlertCircle className="w-4 h-4 text-destructive" />
            <span>Analysis failed: {error}</span>
          </div>
        );
      }

      return (
        <div className="text-sm bg-muted/50 px-3 py-2 rounded-md">
          <span>No UI patterns detected</span>
        </div>
      );
    }

    return (
      <div className="flex flex-wrap gap-2 mt-2">
        {patterns.map((pattern, index) => (
          <div 
            key={index} 
            className="text-sm bg-primary/20 text-primary-foreground px-3 py-1.5 rounded-md"
          >
            <span>{pattern.name}</span>
          </div>
        ))}
      </div>
    );
  };

  // Fix: Move the position: "fixed" out of the variants and into the component style
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
      top: window.innerHeight / 2 - Math.min(selectedImage.height || 600, window.innerHeight * 0.8) / 2,
      left: window.innerWidth / 2 - Math.min(selectedImage.width || 800, window.innerWidth * 0.85) / 2,
      width: Math.min(selectedImage.width || 800, window.innerWidth * 0.85),
      height: Math.min(selectedImage.height || 600, window.innerHeight * 0.8),
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
    <AnimatePresence>
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
            className="fixed z-50 overflow-hidden"
            style={{ position: "fixed" }}
            variants={modalVariants}
            initial="initial"
            animate="open"
            exit="exit"
          >
            <div className="relative w-full h-full bg-background/5 backdrop-blur-lg p-4 rounded-lg overflow-hidden shadow-2xl">
              <motion.button
                className="absolute top-2 right-2 bg-black/40 hover:bg-black/60 text-white rounded-full p-2 z-10"
                onClick={onClose}
                whileHover={{ scale: 1.1 }}
                whileTap={{ scale: 0.9 }}
                initial={{ opacity: 0 }}
                animate={{ opacity: 1, transition: { delay: 0.2 } }}
                exit={{ opacity: 0 }}
              >
                <X className="h-5 w-5" />
              </motion.button>

              <motion.img
                src={selectedImage.url}
                alt="Selected image"
                className="w-full h-full object-contain rounded-md"
                initial={{ opacity: 0.8 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0.8 }}
              />

              {/* Pattern tags - conditionally rendered based on showPatterns state */}
              <AnimatePresence>
                {showPatterns && (
                  <motion.div 
                    className="absolute bottom-0 left-0 right-0 px-4 py-2 bg-background/80 backdrop-blur-sm"
                    initial={{ opacity: 0, y: 10 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={{ opacity: 0, y: 10 }}
                  >
                    {renderPatternTags(selectedImage.patterns, selectedImage.isAnalyzing, selectedImage.error)}
                  </motion.div>
                )}
              </AnimatePresence>
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  );
};

export default AnimatedImageModal;
