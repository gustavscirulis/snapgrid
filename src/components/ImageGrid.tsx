
import React, { useState, useEffect, useRef } from "react";
import { ImageItem } from "@/hooks/useImageStore";
import { ExternalLink, Scan, Trash2, AlertCircle, Link, Globe } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import AnimatedImageModal from "./AnimatedImageModal";
import { motion, AnimatePresence } from "framer-motion";

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
  const [currentPatternElements, setCurrentPatternElements] = useState<React.ReactNode | null>(null);
  
  // Create a map to store refs for each image
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

  const handleUrlClick = (url: string, e: React.MouseEvent) => {
    e.stopPropagation();
    e.preventDefault();
    
    // Open URL in default browser
    if (window.electron && window.electron.openUrl) {
      // In Electron, use shell.openExternal via the electron API
      window.electron.openUrl(url);
    } else {
      // In browser, open in new tab
      window.open(url, '_blank', 'noopener,noreferrer');
    }
  };

  const handleImageClick = (image: ImageItem, ref: React.RefObject<HTMLDivElement>) => {
    if (image.type === "url") {
      return;
    }
    
    // Capture the current pattern elements if they're being shown for this image
    if (hoveredImageId === image.id) {
      const patternEl = document.getElementById(`pattern-tags-${image.id}`);
      if (patternEl) {
        setCurrentPatternElements(patternEl.cloneNode(true).innerHTML);
      }
    } else {
      setCurrentPatternElements(null);
    }
    
    setSelectedImage(image);
    setSelectedImageRef(ref);
    setModalOpen(true);
    onImageClick(image);
  };

  const closeModal = () => {
    setModalOpen(false);
    setTimeout(() => {
      setSelectedImage(null);
      setCurrentPatternElements(null);
    }, 300);
  };

  const renderPatternTags = (item: ImageItem) => {
    if (!item.patterns || item.patterns.length === 0) {
      if (item.isAnalyzing) {
        return (
          <div className="flex items-center gap-1 text-xs text-primary-foreground bg-primary/80 px-2 py-1 rounded-md">
            <Scan className="w-3 h-3 animate-pulse" />
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
    if (item.type === "url") {
      const isLoading = item.isAnalyzing;
      const hasError = item.error;
      
      return (
        <div className="url-card h-full flex flex-col relative group">
          {/* Link indicator badge */}
          <div className="absolute top-2 left-2 z-10 bg-primary/80 text-white p-1 rounded-full">
            <Link className="h-4 w-4" />
          </div>
          
          {/* Card content */}
          <div className="flex flex-col justify-between h-full">
            {/* Main content area */}
            <div className="p-4 flex flex-col h-full relative">
              {/* Background thumbnail/placeholder */}
              <div className="absolute inset-0 overflow-hidden bg-secondary/20">
                {item.thumbnailUrl ? (
                  <img 
                    src={item.thumbnailUrl} 
                    alt={item.title || "Website"} 
                    className="w-full h-full object-cover opacity-20" 
                  />
                ) : (
                  <div className="flex items-center justify-center h-full">
                    <Globe className="h-20 w-20 text-muted-foreground/20" />
                  </div>
                )}
              </div>
              
              {/* Content overlay */}
              <div className="relative z-10 flex flex-col h-full">
                {isLoading && (
                  <div className="absolute inset-0 bg-background/60 flex items-center justify-center">
                    <div className="flex items-center space-x-2">
                      <Scan className="h-4 w-4 animate-pulse text-primary" />
                      <span className="text-sm">Loading metadata...</span>
                    </div>
                  </div>
                )}
                
                {hasError && (
                  <div className="absolute top-2 right-2 z-10">
                    <TooltipProvider>
                      <Tooltip>
                        <TooltipTrigger asChild>
                          <div className="text-destructive">
                            <AlertCircle className="h-4 w-4" />
                          </div>
                        </TooltipTrigger>
                        <TooltipContent>
                          <p>Failed to load metadata</p>
                        </TooltipContent>
                      </Tooltip>
                    </TooltipProvider>
                  </div>
                )}
                
                {/* Content */}
                <div className="mt-12 bg-background/80 p-4 rounded-md flex-grow">
                  <h3 className="font-medium text-base mb-2 line-clamp-2">{item.title || item.url}</h3>
                  
                  {item.description && (
                    <p className="text-xs text-muted-foreground mt-1 line-clamp-3">{item.description}</p>
                  )}
                  
                  <p className="text-xs text-muted-foreground mt-2 truncate">{item.url}</p>
                </div>
              </div>
            </div>
            
            {/* Footer */}
            <div 
              className="p-3 bg-primary text-primary-foreground text-sm font-medium cursor-pointer flex items-center justify-center"
              onClick={(e) => handleUrlClick(item.sourceUrl || item.url, e)}
            >
              <ExternalLink className="w-4 h-4 mr-2" />
              <span>Open URL</span>
            </div>
          </div>
        </div>
      );
    } else {
      // Regular image rendering logic
      return (
        <div className="relative">
          <img
            src={item.url}
            alt="UI Screenshot"
            className="w-full h-auto object-cover rounded-t-lg"
            loading="lazy"
          />
          <AnimatePresence>
            {hoveredImageId === item.id && (
              <motion.div 
                id={`pattern-tags-${item.id}`}
                className="absolute bottom-0 left-0 right-0 p-2 bg-gradient-to-t from-black/60 to-transparent"
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
    }
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

  // Make sure we have refs for all images
  images.forEach(image => {
    if (!imageRefs.current.has(image.id)) {
      imageRefs.current.set(image.id, React.createRef<HTMLDivElement>());
    }
  });

  return (
    <div className="px-4 py-6 w-full">
      {images.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <div className="w-24 h-24 bg-muted rounded-full flex items-center justify-center mb-6">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              className="h-10 w-10 text-muted-foreground"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
            >
              <rect x="3" y="3" width="18" height="18" rx="2" ry="2" />
              <circle cx="8.5" cy="8.5" r="1.5" />
              <polyline points="21 15 16 10 5 21" />
            </svg>
          </div>
          <h3 className="text-2xl font-medium mb-2">No items yet</h3>
          <div className="mt-6 flex gap-3">
            <label 
              htmlFor="file-upload"
              className="inline-flex items-center px-4 py-2 bg-primary text-white rounded-lg hover:bg-primary/90 transition-colors cursor-pointer"
            >
              Upload image
            </label>
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
                {column.map((image) => {
                  const ref = imageRefs.current.get(image.id) || React.createRef<HTMLDivElement>();
                  return (
                    <div key={image.id} className="masonry-item">
                      <motion.div 
                        ref={ref}
                        className={`rounded-lg overflow-hidden bg-white shadow-sm hover:shadow-md transition-all relative group w-full`}
                        onClick={() => image.type !== "url" && handleImageClick(image, ref)}
                        onMouseEnter={() => setHoveredImageId(image.id)}
                        onMouseLeave={() => setHoveredImageId(null)}
                        animate={{
                          opacity: selectedImage?.id === image.id && modalOpen ? 0 : 1
                        }}
                        transition={{ 
                          opacity: { duration: 0.2 }
                        }}
                      >
                        {renderItem(image)}
                        
                        {onImageDelete && (
                          <Button
                            variant="destructive"
                            size="icon"
                            className="absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity p-1.5"
                            onClick={(e) => {
                              e.stopPropagation();
                              onImageDelete(image.id);
                            }}
                          >
                            <Trash2 className="h-4 w-4" />
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
            patternElements={currentPatternElements}
          />
        </>
      )}
    </div>
  );
};

export default ImageGrid;
