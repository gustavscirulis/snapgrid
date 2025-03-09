import React, { useState, useEffect, useRef } from "react";
import { ImageItem } from "@/hooks/useImageStore";
import { X, AlertCircle, ImagePlus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import AnimatedImageModal from "./AnimatedImageModal";
import { useEffect as useFramerEffect } from "framer-motion";
import { motion, AnimatePresence } from "framer-motion";
import { ImageRenderer } from "@/components/ImageRenderer";

interface ImageGridProps {
  images: ImageItem[];
  onImageClick: (image: ImageItem) => void;
  onImageDelete?: (id: string) => void;
}

const ImageGrid: React.FC<ImageGridProps> = ({ images, onImageClick, onImageDelete }) => {
  const [hoveredImageId, setHoveredImageId] = useState<string | null>(null);
  const [columns, setColumns] = useState(3);
  const [selectedImage, setSelectedImage] = useState<ImageItem | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [selectedImageRef, setSelectedImageRef] = useState<React.RefObject<HTMLDivElement> | null>(null);
  const [clickedImageId, setClickedImageId] = useState<string | null>(null);
  const [exitAnimationComplete, setExitAnimationComplete] = useState(false);

  const imageRefs = useRef<Map<string, React.RefObject<HTMLDivElement>>>(new Map());

  useEffect(() => {
    const updateColumns = () => {
      const width = window.innerWidth;
      if (width >= 1536) {
        setColumns(5); // 2xl breakpoint
      } else if (width >= 1280) {
        setColumns(4); // xl breakpoint
      } else if (width >= 1024) {
        setColumns(3); // lg breakpoint
      } else if (width >= 640) {
        setColumns(2); // sm breakpoint
      } else {
        setColumns(1); // xs/mobile
      }
    };

    updateColumns();
    window.addEventListener('resize', updateColumns);
    return () => window.removeEventListener('resize', updateColumns);
  }, []);

  const handleImageClick = (image: ImageItem, ref: React.RefObject<HTMLDivElement>) => {
    // Set the state with the clicked image
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
            className="text-xs bg-secondary text-secondary-foreground px-2 py-0.5 rounded-md"
            title={`Confidence: ${Math.round(pattern.confidence * 100)}%`}
          >
            {pattern.name}
          </span>
        ))}
      </div>
    );
  };

  const renderItem = (item: ImageItem) => {
    return (
      <div className="relative">
        <ImageRenderer 
          image={item}
          alt="UI Screenshot"
          className="w-full h-auto object-cover rounded-t-lg"
          controls={false}
          autoPlay={false}
        />
        <AnimatePresence>
          {hoveredImageId === item.id && (
            <motion.div 
              id={`pattern-tags-${item.id}`}
              className="absolute bottom-0 left-0 right-0 p-2"
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: 10 }}
            >
              {renderPatternTags(item)}
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    );
  };

  const distributeImages = () => {
    const columnArrays: ImageItem[][] = Array.from({ length: columns }, () => []);

    images.forEach((image, index) => {
      const shortestColumnIndex = columnArrays
        .map((column, i) => ({ height: column.length, index: i }))
        .sort((a, b) => a.height - b.height)[0].index;

      columnArrays[shortestColumnIndex].push(image);
    });

    return columnArrays;
  };

  const columnData = distributeImages();

  images.forEach(image => {
    if (!imageRefs.current.has(image.id)) {
      imageRefs.current.set(image.id, React.createRef<HTMLDivElement>());
    }
  });

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
    <div className="px-4 py-6 w-full">
      {images.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <div className="w-24 h-24 bg-muted rounded-full flex items-center justify-center mb-6">
            <ImagePlus className="h-12 w-12 text-muted-foreground" />
          </div>
        </div>
      ) : (
        <>
          <motion.div 
            className="masonry-grid"
            animate={modalOpen ? { opacity: 0.3 } : { opacity: 1 }}
            transition={{ duration: 0.3 }}
          >
            {columnData.map((column, columnIndex) => (
              <div 
                key={columnIndex} 
                className="masonry-column"
                style={{ width: `${100 / columns}%` }}
              >
                {column.map((image, index) => {
                  const ref = imageRefs.current.get(image.id) || React.createRef<HTMLDivElement>();
                  const isSelected = clickedImageId === image.id;
                  return (
                    <div key={image.id} className="masonry-item">
                      <motion.div 
                        ref={ref}
                        className={`rounded-lg overflow-hidden bg-white shadow-sm hover:shadow-md transition-all relative group w-full`}
                        onClick={() => handleImageClick(image, ref)}
                        onMouseEnter={() => setHoveredImageId(image.id)}
                        onMouseLeave={() => setHoveredImageId(null)}
                        animate={{ 
                          opacity: isSelected && modalOpen && !exitAnimationComplete ? 0 : 1
                        }}
                        transition={{ 
                          opacity: { duration: 0.1 }
                        }}
                      >
                        {renderItem(image)}

                        {onImageDelete && (
                          <Button
                            variant="ghost"
                            size="icon"
                            className="absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity p-1.5 rounded-full h-8 w-8 bg-black/60 text-white hover:bg-black/80"
                            onClick={(e) => {
                              e.stopPropagation();
                              onImageDelete(image.id);
                            }}
                          >
                            <X className="h-4 w-4" />
                          </Button>
                        )}
                      </motion.div>
                    </div>
                  );
                })}
              </div>
            ))}
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