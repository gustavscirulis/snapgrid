
import React, { useEffect, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { ImageItem, PatternTag } from "@/hooks/useImageStore";
import { X, Scan, AlertCircle } from "lucide-react";

interface AnimatedImageModalProps {
  isOpen: boolean;
  onClose: () => void;
  selectedImage: ImageItem | null;
  selectedImageRef: React.RefObject<HTMLDivElement> | null;
}

const AnimatedImageModal: React.FC<AnimatedImageModalProps> = ({
  isOpen,
  onClose,
  selectedImage,
  selectedImageRef,
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
      // Reset when closed
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

          {/* Image container */}
          <motion.div
            className="fixed z-50 flex items-center justify-center"
            initial={{
              top: initialPosition.top,
              left: initialPosition.left,
              width: initialPosition.width,
              height: initialPosition.height,
              scale: 1,
            }}
            animate={{
              top: "50%",
              left: "50%",
              width: "auto",
              height: "auto",
              scale: 1,
              y: "-50%",
              x: "-50%",
            }}
            exit={{
              top: initialPosition.top,
              left: initialPosition.left,
              width: initialPosition.width,
              height: initialPosition.height,
              scale: 1,
              y: 0,
              x: 0,
            }}
            transition={{ type: "spring", damping: 25, stiffness: 200 }}
          >
            <div className="relative max-h-[85vh] max-w-[85vw] bg-background/5 backdrop-blur-lg p-4 rounded-lg overflow-hidden shadow-2xl">
              <motion.button
                className="absolute top-2 right-2 bg-black/40 hover:bg-black/60 text-white rounded-full p-2 z-10"
                onClick={onClose}
                whileHover={{ scale: 1.1 }}
                whileTap={{ scale: 0.9 }}
              >
                <X className="h-5 w-5" />
              </motion.button>

              <motion.img
                src={selectedImage.url}
                alt="Selected image"
                className="max-h-[80vh] max-w-full object-contain rounded-md shadow-md"
                initial={{ opacity: 0.5 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0.5 }}
                style={{ 
                  maxWidth: Math.min(selectedImage.width, window.innerWidth * 0.85),
                  maxHeight: Math.min(selectedImage.height, window.innerHeight * 0.8)
                }}
              />

              {selectedImage.patterns && (
                <motion.div 
                  className="mt-4 px-2"
                  initial={{ opacity: 0, y: 10 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ delay: 0.2 }}
                >
                  {renderPatternTags(selectedImage.patterns, selectedImage.isAnalyzing, selectedImage.error)}
                </motion.div>
              )}
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  );
};

export default AnimatedImageModal;
