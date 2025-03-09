import React, { useState, useEffect, useRef } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { ImageItem } from "@/hooks/useImageStore";
import { X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { ImageRenderer } from "@/components/ImageRenderer";

interface AnimatedImageModalProps {
  isOpen: boolean;
  onClose: () => void;
  selectedImage: ImageItem | null;
  selectedImageRef: React.RefObject<HTMLDivElement> | null;
  patternElements: React.ReactElement[] | null;
  onAnimationComplete?: (definition: string) => void;
}

const AnimatedImageModal: React.FC<AnimatedImageModalProps> = ({
  isOpen,
  onClose,
  selectedImage,
  selectedImageRef,
  patternElements,
  onAnimationComplete,
}) => {
  const [isPlaying, setIsPlaying] = useState(false);
  const modalOverlayRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape" && isOpen) {
        onClose();
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => {
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [isOpen, onClose]);

  useEffect(() => {
    if (isOpen) {
      document.body.style.overflow = 'hidden';
    } else {
      document.body.style.overflow = '';
    }
    return () => {
      document.body.style.overflow = '';
    };
  }, [isOpen]);

  const handleClickOutside = (event: MouseEvent) => {
    if (modalOverlayRef.current && !modalOverlayRef.current.contains(event.target as Node)) {
      onClose();
    }
  };

  const modalVariants = {
    hidden: { opacity: 0 },
    visible: { opacity: 1 },
    exit: { opacity: 0 },
  };

  const modalContentVariants = {
    hidden: { y: 50, opacity: 0 },
    visible: { y: 0, opacity: 1 },
    exit: { y: 50, opacity: 0 },
  };

  return (
    <AnimatePresence onExitComplete={() => onAnimationComplete?.("exit-complete")}>
      {isOpen && selectedImage && (
        <motion.div
          ref={modalOverlayRef}
          className="fixed inset-0 bg-black/80 z-50 flex items-center justify-center p-4"
          variants={modalVariants}
          initial="hidden"
          animate="visible"
          exit="exit"
          transition={{ duration: 0.3 }}
          onClick={handleClickOutside}
          onAnimationComplete={() => onAnimationComplete?.("enter")}
          onExit={() => onAnimationComplete?.("exit")}
        >
          <motion.div
            className="relative bg-background rounded-lg shadow-lg max-w-4xl max-h-[90vh] w-full overflow-auto"
            variants={modalContentVariants}
            transition={{ duration: 0.3 }}
            style={{
              width: selectedImage.width ? Math.min(selectedImage.width, 1920) : 'auto',
              height: selectedImage.height ? Math.min(selectedImage.height, 1080) : 'auto',
            }}
          >
            <div className="absolute top-2 right-2">
              <Button variant="ghost" size="icon" onClick={onClose}>
                <X className="h-5 w-5" />
                <span className="sr-only">Close</span>
              </Button>
            </div>

            <div className="p-4">
              <h2 className="text-lg font-semibold mb-2">{selectedImage.title || "Image Preview"}</h2>
              {selectedImage.description && (
                <p className="text-sm text-muted-foreground mb-4">{selectedImage.description}</p>
              )}

              <div className="relative">
                {selectedImage.type === "video" ? (
                  <video
                    src={selectedImage.url}
                    controls
                    autoPlay={isPlaying}
                    className="w-full h-auto object-contain rounded-lg"
                    onClick={() => setIsPlaying(!isPlaying)}
                  />
                ) : (
                  <ImageRenderer 
                    image={selectedImage}
                    alt="Selected image"
                    className="w-full h-auto object-contain rounded-lg"
                    controls={true}
                    autoPlay={isPlaying}
                    muted={false}
                  />
                )}
              </div>

              {patternElements && (
                <div className="mt-4">
                  <h3 className="text-md font-semibold mb-2">Detected UI Patterns:</h3>
                  <div className="flex flex-wrap gap-2">
                    {patternElements}
                  </div>
                </div>
              )}
            </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
};

export default AnimatedImageModal;
