import React, { useState, useEffect, useRef } from "react";
import { ImageItem } from "@/hooks/useImageStore";
import { X, AlertCircle } from "lucide-react";
import { Button } from "@/components/ui/button";
import AnimatedImageModal from "./AnimatedImageModal";
import { motion, AnimatePresence } from "framer-motion";
import { ImageRenderer } from "@/components/ImageRenderer";
import Masonry from 'react-masonry-css';
import './masonry-grid.css'; // We'll create this CSS file

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
        imageRefs.current.set(image.id, React.createRef<HTMLDivElement>());
      }
    });
  }, [images]);
  
  const handleImageClick = (image: ImageItem, ref: React.RefObject<HTMLDivElement>) => {
    setSelectedImage(image);
    setSelectedImageRef(ref);
    setModalOpen(true);
    setClickedImageId(image.id);
    onImageClick(image);
  };

  const closeModal = () => {
    setModalOpen(false);
    setTimeout(() => {
      setSelectedImage(null);
      setClickedImageId(null);
    }, 300);
  };

  const renderPatternTags = (item: ImageItem) => {
    if (!item.patterns || item.patterns.length === 0) {
      if (item.isAnalyzing) {
        return (
          <div className="flex items-center gap-1 text-xs text-primary-foreground bg-primary/80 px-2 py-1 rounded-md">
            <AlertCircle className="w-3 h-3 animate-pulse" />
            <span>Analyzing...</span>
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

  const handleAnimationComplete = (definition: string) => {
    if (definition === "exit") {
      setExitAnimationComplete(true);
    } else if (definition === "exit-complete") {
      setTimeout(() => {
        setExitAnimationComplete(false);
      }, 100);
    }
  };

  return (
    <div className="w-full px-4 py-6">
      {images.length === 0 ? (
        <div className="flex items-center justify-center h-[calc(100vh-200px)] text-center">
          <p className="text-lg text-muted-foreground">
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
                const ref = imageRefs.current.get(image.id) || React.createRef<HTMLDivElement>();
                const isSelected = clickedImageId === image.id;
                
                return (
                  <div key={image.id} className="masonry-item">
                    <motion.div 
                      ref={ref}
                      className="rounded-lg overflow-hidden bg-white shadow-sm hover:shadow-md transition-all relative group w-full"
                      initial={{ opacity: 0, y: 20 }}
                      animate={{ 
                        opacity: isSelected && modalOpen && !exitAnimationComplete ? 0 : 1,
                        y: 0
                      }}
                      transition={{ 
                        opacity: { duration: 0.2 },
                        y: { type: "spring", stiffness: 300, damping: 30 }
                      }}
                      onClick={() => handleImageClick(image, ref)}
                      onMouseEnter={() => setHoveredImageId(image.id)}
                      onMouseLeave={() => setHoveredImageId(null)}
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
                              onImageDelete(image.id);
                            }}
                          >
                            <X className="h-4 w-4" />
                          </Button>
                        )}
                      </div>
                    </motion.div>
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