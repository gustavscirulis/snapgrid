import React, { useState, useEffect, useRef } from "react";
import { ImageItem } from "@/hooks/useImageStore";
import { X, AlertCircle, Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import AnimatedImageModal from "./AnimatedImageModal";
import { motion, AnimatePresence } from "framer-motion";
import { ImageRenderer } from "@/components/ImageRenderer";
import Masonry from 'react-masonry-css';
import './masonry-grid.css'; // We'll create this CSS file
import './text-shine.css'; // Import the text shine animation CSS

interface ImageGridProps {
  images: ImageItem[];
  onImageClick: (image: ImageItem) => void;
  onImageDelete?: (id: string) => void;
}

const ImageGrid: React.FC<ImageGridProps> = ({ images, onImageClick, onImageDelete }) => {
  const [hoveredImageId, setHoveredImageId] = useState<string | null>(null);
  const [selectedImage, setSelectedImage] = useState<ImageItem | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [selectedImageRef, setSelectedImageRef] = useState<React.RefObject<HTMLDivElement> | null>(null);
  const [clickedImageId, setClickedImageId] = useState<string | null>(null);
  const [exitAnimationComplete, setExitAnimationComplete] = useState(false);
  const [isAnimating, setIsAnimating] = useState(false);
  
  // Image refs for animations
  const imageRefs = useRef<Map<string, React.RefObject<HTMLDivElement>>>(new Map());
  
  // Responsive breakpoints for the masonry grid - fewer columns for bigger thumbnails
  const breakpointColumnsObj = {
    default: 4, // Default column count (large screens) - reduced from 5 to 4
    1536: 4,    // 2xl breakpoint - reduced from 5 to 4
    1280: 3,    // xl breakpoint - reduced from 4 to 3
    1024: 2,    // lg breakpoint - reduced from 3 to 2
    640: 1,     // sm breakpoint - reduced from 2 to 1
    480: 1      // xs/mobile
  };
  
  // Initialize image refs
  useEffect(() => {
    images.forEach(image => {
      if (!imageRefs.current.has(image.id)) {
        const ref = React.createRef<HTMLDivElement>();
        console.log('Creating ref for image:', image.id);
        imageRefs.current.set(image.id, ref);
      }
    });
  }, [images]);
  
  // Reset exitAnimationComplete after a delay
  useEffect(() => {
    if (exitAnimationComplete) {
      const timeoutId = setTimeout(() => {
        setExitAnimationComplete(false);
      }, 300);
      return () => clearTimeout(timeoutId);
    }
  }, [exitAnimationComplete]);
  
  const handleImageClick = (image: ImageItem, ref: React.RefObject<HTMLDivElement>) => {
    if (isAnimating) return; // Prevent clicks during animation
    
    setIsAnimating(true);
    setSelectedImage(image);
    setSelectedImageRef(ref);
    setModalOpen(true);
    setClickedImageId(image.id);
    onImageClick(image);
  };

  const handleAnimationComplete = (definition: string) => {
    if (definition === "exit") {
      setExitAnimationComplete(true);
      // Reset all states immediately instead of using a timeout
      setIsAnimating(false);
      setClickedImageId(null);
    }
  };

  const closeModal = () => {
    setModalOpen(false);
    // Make thumbnail immediately visible
    setClickedImageId(null);
    setExitAnimationComplete(true);
  };

  const handleDeleteImage = (id: string) => {
    onImageDelete?.(id);
  };

  const renderPatternTags = (item: ImageItem) => {
    if (!item.patterns || item.patterns.length === 0) {
      if (item.isAnalyzing) {
        return (
          <div className="inline-flex items-center gap-1 text-xs text-primary-background bg-secondary px-2 py-1 rounded-md">
            <Loader2 className="w-3 h-3 animate-spin text-muted-foreground" />
            <span className="text-shine">Analyzing...</span>
          </div>
        );
      }
      if (item.error) {
        return (
          <div className="flex items-center gap-1 text-xs text-destructive-foreground bg-destructive/80 px-2 py-1 rounded-md">
            <AlertCircle className="w-3 h-3" />
            <span>Analysis failed</span>
          </div>
        );
      }
      return null;
    }

    return (
      <div className="flex flex-wrap gap-1 mt-2">
        {item.patterns.map((pattern, index) => (
          <span 
            key={index} 
            className="text-xs bg-secondary text-secondary-foreground px-2 py-0.5 rounded-md cursor-default"
            title={`Confidence: ${Math.round(pattern.confidence * 100)}%`}
          >
            {pattern.name}
          </span>
        ))}
      </div>
    );
  };

  return (
    <div className="w-full px-4 py-4 flex-1 flex flex-col min-h-0">
      {images.length === 0 ? (
        <div className="flex-1 flex items-center justify-center text-center min-h-0">
          <p className="text-sm text-muted-foreground">
            Drag and drop images or videos here
          </p>
        </div>
      ) : (
        <>
          <motion.div 
            animate={modalOpen ? { opacity: 0.3 } : { opacity: 1 }}
            transition={{ duration: 0.3 }}
            className="w-full"
            style={{ maxWidth: "none" }}
          >
            <Masonry
              breakpointCols={breakpointColumnsObj}
              className="my-masonry-grid"
              columnClassName="my-masonry-grid_column"
            >
              {images.map((image) => {
                let ref = imageRefs.current.get(image.id);
                if (!ref) {
                  ref = React.createRef<HTMLDivElement>();
                  imageRefs.current.set(image.id, ref);
                }
                
                const isSelected = clickedImageId === image.id;
                
                return (
                  <div key={image.id} className="masonry-item">
                    <div 
                      ref={ref}
                      className="rounded-lg overflow-hidden bg-white shadow-sm hover:shadow-md relative group w-full"
                      onClick={() => handleImageClick(image, ref)}
                      onMouseEnter={() => setHoveredImageId(image.id)}
                      onMouseLeave={() => setHoveredImageId(null)}
                      style={{
                        opacity: isSelected && !exitAnimationComplete ? 0 : 1,
                        visibility: isSelected && !exitAnimationComplete ? 'hidden' : 'visible',
                        pointerEvents: isAnimating ? 'none' : 'auto',
                        transition: modalOpen ? 'opacity 0.3s ease-out, visibility 0.3s ease-out' : 'none'
                      }}
                    >
                      <div className="relative">
                        <ImageRenderer 
                          image={image}
                          alt="UI Screenshot"
                          className="w-full h-auto object-cover rounded-t-lg"
                          controls={false}
                          autoPlay={false}
                        />
                        
                        <AnimatePresence>
                          {hoveredImageId === image.id && (
                            <motion.div 
                              id={`pattern-tags-${image.id}`}
                              className={`absolute bottom-0 left-0 right-0 p-2 ${image.type === 'image' ? 'bg-gradient-to-t from-black/50 to-transparent' : ''}`}
                              initial={{ opacity: 0, y: 10 }}
                              animate={{ opacity: 1, y: 0 }}
                              exit={{ opacity: 0, y: 10 }}
                              style={{ 
                                bottom: '-2px'
                              }}
                            >
                              {renderPatternTags(image)}
                            </motion.div>
                          )}
                        </AnimatePresence>
                        
                        {onImageDelete && (
                          <Button
                            variant="ghost"
                            size="icon"
                            className="absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity p-1.5 rounded-full h-8 w-8 bg-black/60 text-white hover:text-white hover:bg-black/80"
                            onClick={(e) => {
                              e.stopPropagation();
                              handleDeleteImage(image.id);
                            }}
                          >
                            <X className="h-4 w-4" />
                          </Button>
                        )}
                      </div>
                    </div>
                  </div>
                );
              })}
            </Masonry>
          </motion.div>

          <AnimatedImageModal
            isOpen={modalOpen}
            onClose={closeModal}
            selectedImage={selectedImage}
            selectedImageRef={selectedImageRef}
            patternElements={null}
            onAnimationComplete={handleAnimationComplete}
          />
        </>
      )}
    </div>
  );
};

export default ImageGrid;