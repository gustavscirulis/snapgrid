import React, { useState, useEffect, useRef } from "react";
import { ImageItem } from "@/hooks/useImageStore";
import { X, AlertCircle, Loader2, Key, Upload } from "lucide-react";
import { Button } from "@/components/ui/button";
import AnimatedImageModal from "./AnimatedImageModal";
import { motion, AnimatePresence } from "framer-motion";
import { ImageRenderer } from "@/components/ImageRenderer";
import Masonry from 'react-masonry-css';
import './masonry-grid.css'; // We'll create this CSS file
import './text-shine.css'; // Import the text shine animation CSS
import { hasApiKey } from "@/services/aiAnalysisService";
import { useDragContext } from "./UploadZone";

interface ImageGridProps {
  images: ImageItem[];
  onImageClick: (image: ImageItem) => void;
  onImageDelete?: (id: string) => void;
  searchQuery?: string;
  onOpenSettings?: () => void;
  settingsOpen?: boolean;
}

const ImageGrid: React.FC<ImageGridProps> = ({ images, onImageClick, onImageDelete, searchQuery = "", onOpenSettings, settingsOpen = false }) => {
  const [hoveredImageId, setHoveredImageId] = useState<string | null>(null);
  const [selectedImage, setSelectedImage] = useState<ImageItem | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [selectedImageRef, setSelectedImageRef] = useState<React.RefObject<HTMLDivElement> | null>(null);
  const [clickedImageId, setClickedImageId] = useState<string | null>(null);
  const [exitAnimationComplete, setExitAnimationComplete] = useState(false);
  const [isAnimating, setIsAnimating] = useState(false);
  const [hasOpenAIKey, setHasOpenAIKey] = useState<boolean | null>(null);
  
  // Image refs for animations
  const imageRefs = useRef<Map<string, React.RefObject<HTMLDivElement>>>(new Map());
  
  // Get drag context with fallback for when context is not available
  const dragContext = { isDragging: false };
  try {
    const context = useDragContext();
    if (context) {
      Object.assign(dragContext, context);
    }
  } catch (error) {
    // Context not available, use default (not dragging)
    console.log("Drag context not available, using default");
  }
  
  // Check if the OpenAI API key is set
  useEffect(() => {
    const checkApiKey = async () => {
      const exists = await hasApiKey();
      setHasOpenAIKey(exists);
    };
    
    checkApiKey();
  }, []);
  
  // Recheck API key when settings panel closes
  useEffect(() => {
    if (settingsOpen === false) {
      // When settings panel closes, check if API key status has changed
      const checkApiKey = async () => {
        const exists = await hasApiKey();
        setHasOpenAIKey(exists);
      };
      
      checkApiKey();
    }
  }, [settingsOpen]);
  
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
        {item.patterns
          .slice(0, 5) // Only display top 5 patterns (already sorted by confidence in aiAnalysisService.ts)
          .map((pattern, index) => (
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

  // Empty state placeholder masonry
  const renderEmptyStatePlaceholders = () => {
    const { isDragging } = dragContext;
    
    // Define possible height ranges
    const heightRanges = [
      { min: 150, max: 250 },  // Short
      { min: 250, max: 350 },  // Medium
      { min: 350, max: 450 }   // Tall
    ];
    
    // Shuffle array function to randomize order
    const shuffleArray = (array: number[]) => {
      for (let i = array.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [array[i], array[j]] = [array[j], array[i]];
      }
      return array;
    };
    
    // Create array of indexes and shuffle them
    const indexes = shuffleArray([...Array(12)].map((_, i) => i));
    
    return (
      <Masonry
        breakpointCols={breakpointColumnsObj}
        className={`my-masonry-grid ${isDragging ? 'opacity-30 blur-[1px]' : 'opacity-50'} transition-all duration-300`}
        columnClassName="my-masonry-grid_column"
      >
        {Array.from({ length: 12 }).map((_, index) => {
          // Use the shuffled index to get more randomized heights
          const heightIndex = indexes[index] % 3;
          const range = heightRanges[heightIndex];
          const height = range.min + Math.floor(Math.random() * (range.max - range.min));
          
          return (
            <div key={index} className="masonry-item">
              <motion.div 
                className="rounded-lg overflow-hidden bg-gray-200 dark:bg-gray-800 w-full transition-all duration-300"
                style={{ height: `${height}px` }}
                initial={{ opacity: 0 }}
                animate={{ opacity: isDragging ? 0.2 : 0.5 }}
                transition={{ 
                  opacity: { duration: 0.5, delay: index * 0.05 }
                }}
              />
            </div>
          );
        })}
      </Masonry>
    );
  };

  // Empty state card for API key setup or drag-drop instruction
  const renderEmptyStateCard = () => {
    // Get the drag state from context
    const { isDragging } = dragContext;
    
    return (
      <motion.div 
        className={`bg-white/95 dark:bg-zinc-900/95 backdrop-blur-sm shadow-2xl rounded-xl w-full overflow-hidden pointer-events-auto border border-gray-200 dark:border-zinc-800 transition-all duration-300 ${
          isDragging ? 'opacity-80 blur-[1px]' : 'opacity-100'
        }`}
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: isDragging ? 0.8 : 1, y: 0 }}
        transition={{ delay: 0.2, duration: 0.4 }}
      >
        {hasOpenAIKey === null ? (
          // Loading state
          <div className="p-6">
            <div className="animate-pulse flex space-x-4">
              <div className="flex-1 space-y-4 py-1">
                <div className="h-4 bg-gray-200 dark:bg-gray-700 rounded w-3/4"></div>
                <div className="space-y-2">
                  <div className="h-4 bg-gray-200 dark:bg-gray-700 rounded"></div>
                  <div className="h-4 bg-gray-200 dark:bg-gray-700 rounded w-5/6"></div>
                </div>
              </div>
            </div>
          </div>
        ) : hasOpenAIKey ? (
          // API key is set - show drag and drop instructions
          <>
            <div className="p-8">
              <div className="rounded-full bg-gray-100 dark:bg-zinc-800 w-14 h-14 flex items-center justify-center mb-5">
                <Upload className="h-7 w-7 text-gray-600 dark:text-gray-400" />
              </div>
              <h3 className="text-xl font-semibold text-gray-900 dark:text-gray-100 mb-3">
                Drag and drop images or videos here
              </h3>
              <p className="text-sm text-gray-600 dark:text-gray-400 mb-4">
                They will be automatically analysed for UI patterns and organised.
              </p>
            </div>
            <div className="bg-gray-50 dark:bg-zinc-800/50 px-6 py-4 border-t border-gray-200 dark:border-zinc-800">
              <p className="text-xs text-gray-700 dark:text-gray-300">
                You can also paste images from clipboard (⌘+V)
              </p>
            </div>
          </>
        ) : (
          // No API key - show add API key card
          <>
            <div className="p-8">
              <div className="rounded-full bg-gray-100 dark:bg-zinc-800 w-14 h-14 flex items-center justify-center mb-5">
                <Key className="h-7 w-7 text-gray-600 dark:text-gray-400" />
              </div>
              <h3 className="text-xl font-semibold text-gray-900 dark:text-gray-100 mb-3">
                Add an OpenAI API key
              </h3>
              <p className="text-sm text-gray-600 dark:text-gray-400 mb-6">
                Unlock automatic pattern detection in screenshots by adding your OpenAI API key.
              </p>
              <Button 
                onClick={() => {
                  onOpenSettings?.();
                }}
                className="w-full bg-gray-800 hover:bg-gray-900 dark:bg-gray-700 dark:hover:bg-gray-600 text-white py-5 text-base font-medium"
              >
                Add API Key
              </Button>
            </div>
            <div className="bg-gray-50 dark:bg-zinc-800/50 px-6 py-4 border-t border-gray-200 dark:border-zinc-800">
              <p className="text-xs text-gray-700 dark:text-gray-300">
                You can still upload and organize screenshots without an API key.
              </p>
            </div>
          </>
        )}
      </motion.div>
    );
  };

  return (
    <div className={`w-full px-4 py-4 flex-1 flex flex-col ${images.length === 0 && !searchQuery ? 'overflow-hidden' : ''}`}>
      {/* Debug info - remove in production */}
      <div className="hidden">{`Images: ${images.length}, HasKey: ${hasOpenAIKey}, IsSearching: ${searchQuery !== ""}`}</div>
      
      {images.length === 0 ? (
        <div className="flex-1 flex items-stretch">
          {searchQuery ? (
            <div className="flex justify-center items-center w-full min-h-[50vh]">
              <p className="text-sm text-muted-foreground">
                Nothing found
              </p>
            </div>
          ) : (
            <>
              {/* Background masonry grid */}
              <div className="absolute inset-0 pt-20 pb-4 px-4 overflow-hidden">
                {renderEmptyStatePlaceholders()}
              </div>
              
              {/* Fixed centered card */}
              <div className="fixed top-0 left-0 right-0 bottom-0 flex items-center justify-center pointer-events-none z-[100]" style={{ paddingTop: "20px" }}>
                {!settingsOpen && (
                  <div className="max-w-lg w-full mx-4 pointer-events-auto" style={{ marginTop: "-50px" }}>
                    {renderEmptyStateCard()}
                  </div>
                )}
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