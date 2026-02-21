import React, { useState, useEffect, useRef } from "react";
import { ImageItem } from "@/hooks/useImageStore";
import { X } from "lucide-react";
import { Button } from "@/components/ui/button";
import AnimatedImageModal from "./AnimatedImageModal";
import { motion, AnimatePresence } from "framer-motion";
import { ImageRenderer } from "@/components/ImageRenderer";
import Masonry from 'react-masonry-css';
import './masonry-grid.css';
import './text-shine.css';
import { useDragContext } from "./UploadZone";
import { useImagePreloader } from "@/hooks/useImagePreloader";
import { useApiKeyWatcher } from "@/hooks/useApiKeyWatcher";
import PatternTags from "./PatternTags";
import EmptyStateCard from "./EmptyStateCard";
import EmptyStatePlaceholders from "./EmptyStatePlaceholders";

interface ImageGridProps {
  images: ImageItem[];
  onImageClick: (image: ImageItem) => void;
  onImageDelete?: (id: string) => void;
  searchQuery?: string;
  onOpenSettings?: () => void;
  settingsOpen?: boolean;
  retryAnalysis?: (imageId: string) => Promise<void>;
  thumbnailSize?: 'small' | 'medium' | 'large' | 'xl';
}

const ImageGrid: React.FC<ImageGridProps> = ({ images, onImageClick, onImageDelete, searchQuery = "", onOpenSettings, settingsOpen = false, retryAnalysis, thumbnailSize = 'medium' }) => {
  const [hoveredImageId, setHoveredImageId] = useState<string | null>(null);
  const [selectedImage, setSelectedImage] = useState<ImageItem | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [selectedImageRef, setSelectedImageRef] = useState<React.RefObject<HTMLDivElement> | null>(null);
  const [clickedImageId, setClickedImageId] = useState<string | null>(null);
  const [exitAnimationComplete, setExitAnimationComplete] = useState(false);
  const [isAnimating, setIsAnimating] = useState(false);

  // Image refs for animations
  const imageRefs = useRef<Map<string, React.RefObject<HTMLDivElement>>>(new Map());

  // Initialize image preloader
  const preloader = useImagePreloader(images, {
    rootMargin: '1000px',
    threshold: 0.1,
    preloadDistance: 5
  });

  // Get drag context (useContext never throws — returns default value if no Provider)
  const dragContext = useDragContext();

  // API key watching and batch analysis
  const { hasOpenAIKey } = useApiKeyWatcher({ settingsOpen, images, retryAnalysis });

  // Prevent scrolling when in empty state
  useEffect(() => {
    // Only add the no-scroll style when we're in empty state and not searching
    if (images.length === 0 && !searchQuery) {
      document.body.style.overflow = 'hidden';
    } else {
      document.body.style.overflow = '';
    }
    
    return () => {
      document.body.style.overflow = '';
    };
  }, [images.length, searchQuery]);
  

  // Dynamic responsive breakpoints based on thumbnail size
  const getBreakpointColumnsObj = () => {
    switch (thumbnailSize) {
      case 'small':
        return {
          default: 6, // More columns for smaller thumbnails
          1536: 6,
          1280: 5,
          1024: 4,
          640: 3,
          480: 2
        };
      case 'medium':
        return {
          default: 4, // Default size
          1536: 4,
          1280: 3,
          1024: 2,
          640: 1,
          480: 1
        };
      case 'large':
        return {
          default: 3, // Fewer columns for larger thumbnails
          1536: 3,
          1280: 2,
          1024: 2,
          640: 1,
          480: 1
        };
      case 'xl':
        return {
          default: 2, // Very few columns for extra large thumbnails
          1536: 2,
          1280: 2,
          1024: 1,
          640: 1,
          480: 1
        };
      default:
        return {
          default: 4,
          1536: 4,
          1280: 3,
          1024: 2,
          640: 1,
          480: 1
        };
    }
  };

  const breakpointColumnsObj = getBreakpointColumnsObj();
  
  // Initialize image refs and setup intersection observer
  useEffect(() => {
    images.forEach(image => {
      if (!imageRefs.current.has(image.id)) {
        const ref = React.createRef<HTMLDivElement>();
        imageRefs.current.set(image.id, ref);
      }
    });

    // Setup intersection observer for existing refs
    const timeoutId = setTimeout(() => {
      imageRefs.current.forEach((ref, imageId) => {
        if (ref.current) {
          preloader.observeElement(ref.current, imageId);
        }
      });
    }, 0);

    // Cleanup observers for removed images
    return () => {
      clearTimeout(timeoutId);
      const currentImageIds = new Set(images.map(img => img.id));
      for (const [imageId] of imageRefs.current) {
        if (!currentImageIds.has(imageId)) {
          preloader.unobserveElement(imageId);
          imageRefs.current.delete(imageId);
        }
      }
    };
  }, [images, preloader]);
  
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
      setIsAnimating(false);
      setClickedImageId(null);
    }
  };

  const closeModal = () => {
    setModalOpen(false);
    // Don't reset clickedImageId here - wait for animation to complete
    // The thumbnail should stay hidden until handleAnimationComplete is called
  };

  const handleDeleteImage = (id: string) => {
    onImageDelete?.(id);
  };

  // Memoize placeholder heights to prevent constant re-rendering
  const placeholderHeights = React.useMemo(() => {
    const heightRanges = [
      { min: 150, max: 250 },
      { min: 250, max: 350 },
      { min: 350, max: 450 }
    ];

    return Array.from({ length: 12 }).map((_, index) => {
      const heightIndex = index % 3;
      const range = heightRanges[heightIndex];
      return range.min + Math.floor(Math.random() * (range.max - range.min));
    });
  }, []);

  return (
    <div className={`w-full px-4 pb-4 flex-1 flex flex-col bg-gray-100 dark:bg-zinc-900 ${images.length === 0 && !searchQuery ? 'overflow-hidden' : ''}`}>
      {images.length === 0 ? (
        <div className="flex-1 flex items-stretch">
          {searchQuery ? (
            <div className="flex justify-center items-center w-full min-h-[50vh]">
              <p className="text-sm text-muted-foreground select-none">
                Nothing found
              </p>
            </div>
          ) : (
            <>
              {/* Background masonry grid */}
              <div className="absolute inset-0 pt-20 pb-4 px-4 overflow-hidden bg-gray-100 dark:bg-zinc-900">
                <EmptyStatePlaceholders
                  breakpointColumnsObj={breakpointColumnsObj}
                  isDragging={dragContext.isDragging}
                  placeholderHeights={placeholderHeights}
                />
              </div>

              {/* Fixed centered card */}
              <div className="fixed top-0 left-0 right-0 bottom-0 flex items-center justify-center pointer-events-none z-[100]" style={{ paddingTop: "20px" }}>
                <AnimatePresence>
                  {!settingsOpen && (
                    <motion.div
                      className="max-w-lg w-full mx-4 pointer-events-auto"
                      style={{ marginTop: "-50px" }}
                      initial={{ opacity: 0, y: 20 }}
                      animate={{ opacity: 1, y: 0 }}
                      exit={{ opacity: 0, y: 20 }}
                      transition={{ duration: 0.3 }}
                    >
                      <EmptyStateCard
                        hasOpenAIKey={hasOpenAIKey}
                        isDragging={dragContext.isDragging}
                        onOpenSettings={onOpenSettings}
                      />
                    </motion.div>
                  )}
                </AnimatePresence>
              </div>
            </>
          )}
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
                      className="rounded-lg overflow-hidden bg-gray-100 dark:bg-zinc-800 shadow-sm hover:shadow-md relative group w-full"
                      onClick={() => handleImageClick(image, ref)}
                      onMouseEnter={() => setHoveredImageId(image.id)}
                      onMouseLeave={() => setHoveredImageId(null)}
                      style={{
                        opacity: isSelected ? 0 : 1,
                        visibility: isSelected ? 'hidden' : 'visible',
                        pointerEvents: isAnimating ? 'none' : 'auto'
                      }}
                    >
                      <div className="relative">
                        <ImageRenderer
                          image={image}
                          alt="UI Screenshot"
                          className="w-full h-auto object-cover rounded-t-lg"
                          controls={false}
                          autoPlay={false}
                          preloader={preloader}
                        />

                        <AnimatePresence>
                          {hoveredImageId === image.id && (
                            <motion.div
                              id={`pattern-tags-${image.id}`}
                              className="absolute bottom-0 left-0 right-0 p-2 bg-gradient-to-t from-black/70 to-transparent"
                              initial={{ opacity: 0, y: 10 }}
                              animate={{ opacity: 1, y: 0 }}
                              exit={{ opacity: 0, y: 10 }}
                              style={{
                                bottom: '-2px',
                                pointerEvents: 'none'
                              }}
                            >
                              <div className="pointer-events-auto">
                                <PatternTags item={image} retryAnalysis={retryAnalysis} />
                              </div>
                            </motion.div>
                          )}
                        </AnimatePresence>
                        
                        {/* Video indicator icon */}
                        {image.type === 'video' && (
                          <div className="absolute bottom-2 right-2 bg-black/70 p-1 rounded text-white text-xs z-10">
                            <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 20 20" xmlns="http://www.w3.org/2000/svg">
                              <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM9.555 7.168A1 1 0 008 8v4a1 1 0 001.555.832l3-2a1 1 0 000-1.664l-3-2z" clipRule="evenodd"></path>
                            </svg>
                          </div>
                        )}
                        
                        {onImageDelete && (
                          <Button
                            variant="ghost"
                            size="icon"
                            className="absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity p-1 rounded-full h-6 w-6 bg-black/60 text-white hover:text-white hover:bg-black/80"
                            onClick={(e) => {
                              e.stopPropagation();
                              handleDeleteImage(image.id);
                            }}
                          >
                            <X className="h-3 w-3" />
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