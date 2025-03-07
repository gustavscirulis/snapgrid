
import React, { useEffect, useState, useRef } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { ImageItem } from "@/hooks/useImageStore";
import { Play, Pause, Volume2, VolumeX } from "lucide-react";
import { Button } from "@/components/ui/button";

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
  
  const [isPlaying, setIsPlaying] = useState(false);
  const [isMuted, setIsMuted] = useState(false);
  const videoRef = useRef<HTMLVideoElement>(null);

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
      
      // Auto-play video when modal opens
      if (selectedImage?.type === "video" && videoRef.current) {
        videoRef.current.play().then(() => {
          setIsPlaying(true);
        }).catch(err => {
          console.error("Failed to autoplay video:", err);
        });
      }
    } else {
      document.body.style.overflow = "";
      
      // Pause video when modal closes
      if (selectedImage?.type === "video" && videoRef.current) {
        videoRef.current.pause();
        setIsPlaying(false);
      }
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
  }, [isOpen, onClose, selectedImage]);

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
      // Increase image size by reducing the margin from window edges
      top: window.innerHeight / 2 - Math.min(selectedImage.height || 600, window.innerHeight * 0.95) / 2,
      left: window.innerWidth / 2 - Math.min(selectedImage.width || 800, window.innerWidth * 0.98) / 2,
      width: Math.min(selectedImage.width || 800, window.innerWidth * 0.98),
      height: Math.min(selectedImage.height || 600, window.innerHeight * 0.95),
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

  const togglePlayPause = (e: React.MouseEvent) => {
    e.stopPropagation(); // Prevent closing the modal
    
    if (!videoRef.current) return;
    
    if (isPlaying) {
      videoRef.current.pause();
    } else {
      videoRef.current.play();
    }
    
    setIsPlaying(!isPlaying);
  };

  const toggleMute = (e: React.MouseEvent) => {
    e.stopPropagation(); // Prevent closing the modal
    
    if (!videoRef.current) return;
    
    videoRef.current.muted = !isMuted;
    setIsMuted(!isMuted);
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

          {/* Media container - fixed position applied directly to the element */}
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
            {selectedImage.type === "video" ? (
              <div className="relative w-full h-full">
                <motion.video
                  ref={videoRef}
                  src={selectedImage.url}
                  className="w-full h-full object-contain rounded-lg"
                  controls={false}
                  playsInline
                  initial={{ opacity: 0.8 }}
                  animate={{ opacity: 1 }}
                  exit={{ opacity: 0.8 }}
                />
                
                {/* Video controls */}
                <div 
                  className="absolute bottom-4 left-1/2 transform -translate-x-1/2 bg-black/50 rounded-full flex items-center px-4 py-2 space-x-2"
                  onClick={(e) => e.stopPropagation()} // Prevent modal from closing
                >
                  <Button
                    variant="ghost"
                    size="icon"
                    className="h-8 w-8 text-white hover:bg-white/20"
                    onClick={togglePlayPause}
                  >
                    {isPlaying ? (
                      <Pause className="h-5 w-5" />
                    ) : (
                      <Play className="h-5 w-5" />
                    )}
                  </Button>
                  
                  <Button
                    variant="ghost"
                    size="icon"
                    className="h-8 w-8 text-white hover:bg-white/20"
                    onClick={toggleMute}
                  >
                    {isMuted ? (
                      <VolumeX className="h-5 w-5" />
                    ) : (
                      <Volume2 className="h-5 w-5" />
                    )}
                  </Button>
                </div>
              </div>
            ) : (
              <motion.img
                src={selectedImage.url}
                alt="Selected image"
                className="w-full h-full object-contain rounded-lg"
                initial={{ opacity: 0.8 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0.8 }}
              />
            )}
          </motion.div>
        </>
      )}
    </AnimatePresence>
  );
};

export default AnimatedImageModal;
