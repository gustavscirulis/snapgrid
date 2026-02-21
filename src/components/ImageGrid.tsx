import React, { useState, useEffect, useRef, useCallback } from "react";
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
import { Space } from "@/hooks/useSpaces";
import {
  ContextMenu,
  ContextMenuTrigger,
  ContextMenuContent,
  ContextMenuItem,
  ContextMenuSeparator,
  ContextMenuSub,
  ContextMenuSubTrigger,
  ContextMenuSubContent,
} from "@/components/ui/context-menu";

interface ImageGridProps {
  images: ImageItem[];
  onImageClick: (image: ImageItem) => void;
  onImageDelete?: (id: string) => void;
  searchQuery?: string;
  onOpenSettings?: () => void;
  settingsOpen?: boolean;
  retryAnalysis?: (imageId: string) => Promise<void>;
  thumbnailSize?: 'small' | 'medium' | 'large' | 'xl';
  spaces?: Space[];
  activeSpaceId?: string | null;
  onAssignToSpace?: (imageId: string, spaceId: string | null) => Promise<void>;
}

const ImageGrid: React.FC<ImageGridProps> = ({ images, onImageClick, onImageDelete, searchQuery = "", onOpenSettings, settingsOpen = false, retryAnalysis, thumbnailSize = 'medium', spaces = [], activeSpaceId, onAssignToSpace }) => {
  const [hoveredImageId, setHoveredImageId] = useState<string | null>(null);
  const [selectedImage, setSelectedImage] = useState<ImageItem | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [selectedImageRef, setSelectedImageRef] = useState<React.RefObject<HTMLDivElement> | null>(null);
  const [initialRect, setInitialRect] = useState<{ top: number; left: number; width: number; height: number } | null>(null);
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

  // Only show the full onboarding empty state when there's no active space filter
  const isSpaceFilteredEmpty = images.length === 0 && activeSpaceId != null;

  // Prevent scrolling when in empty state (but not when a space is just empty)
  useEffect(() => {
    if (images.length === 0 && !searchQuery && !activeSpaceId) {
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
    if (isAnimating || justDraggedRef.current) return;

    // Measure thumbnail rect BEFORE any state changes hide it.
    // This lets the modal render in the same paint frame.
    const rect = ref.current?.getBoundingClientRect();
    if (!rect) return;

    // For videos, read actual dimensions from the thumbnail <video> element
    // so the modal can target the correct size from frame 1 (no mid-animation redirect).
    let imageWithDimensions = image;
    if (image.type === 'video') {
      const videoEl = ref.current?.querySelector('video');
      if (videoEl instanceof HTMLVideoElement && videoEl.videoWidth && videoEl.videoHeight) {
        imageWithDimensions = { ...image, width: videoEl.videoWidth, height: videoEl.videoHeight };
      }
    }

    setIsAnimating(true);
    setSelectedImage(imageWithDimensions);
    setSelectedImageRef(ref);
    setInitialRect({ top: rect.top, left: rect.left, width: rect.width, height: rect.height });
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

  // Custom mouse-based drag system for drag-to-space and drag-out-of-app.
  // We avoid HTML5 drag because Electron's startDrag (needed for desktop export)
  // is incompatible with it — startDrag takes over and fires dragend immediately.
  const customDragRef = useRef<{
    image: ImageItem;
    startX: number;
    startY: number;
    isDragging: boolean;
    nativeDragStarted: boolean;
    previewEl: HTMLDivElement | null;
    lastHighlightedTab: HTMLElement | null;
    cleanupTimer: ReturnType<typeof setTimeout> | null;
  } | null>(null);
  const justDraggedRef = useRef(false);

  // Stable refs for callbacks used in the global mouse event effect
  const onAssignToSpaceRef = useRef(onAssignToSpace);
  onAssignToSpaceRef.current = onAssignToSpace;
  const setDraggedImageIdRef = useRef(dragContext.setDraggedImageId);
  setDraggedImageIdRef.current = dragContext.setDraggedImageId;
  const setInternalDragActiveRef = useRef(dragContext.setInternalDragActive);
  setInternalDragActiveRef.current = dragContext.setInternalDragActive;

  const handleImageMouseDown = useCallback((e: React.MouseEvent, image: ImageItem) => {
    if (e.button !== 0) return;
    if ((e.target as HTMLElement).closest('button, input, a, [role="menuitem"]')) return;

    customDragRef.current = {
      image,
      startX: e.clientX,
      startY: e.clientY,
      isDragging: false,
      nativeDragStarted: false,
      previewEl: null,
      lastHighlightedTab: null,
      cleanupTimer: null,
    };
  }, []);

  // Global mousemove/mouseup for custom drag behavior
  useEffect(() => {
    const cleanupDrag = () => {
      const state = customDragRef.current;
      if (!state) return;

      if (state.previewEl) state.previewEl.remove();
      if (state.cleanupTimer) clearTimeout(state.cleanupTimer);
      if (state.lastHighlightedTab) {
        state.lastHighlightedTab.removeAttribute('data-drag-over');
      }
      if (state.isDragging) {
        setDraggedImageIdRef.current(null);
        setInternalDragActiveRef.current(false);
      }
      document.body.style.cursor = '';
      customDragRef.current = null;
    };

    const handleMouseMove = (e: MouseEvent) => {
      const state = customDragRef.current;
      if (!state) return;

      // After native drag handed off to OS, detect when mouse button is released
      // (drag completed) by checking e.buttons on the next mousemove in our window.
      if (state.nativeDragStarted) {
        if (e.buttons === 0) {
          cleanupDrag();
          justDraggedRef.current = false;
        }
        return;
      }

      if (!state.isDragging) {
        const dx = e.clientX - state.startX;
        const dy = e.clientY - state.startY;
        if (dx * dx + dy * dy < 25) return; // 5px threshold

        // Enter drag mode
        state.isDragging = true;
        justDraggedRef.current = true;
        setDraggedImageIdRef.current(state.image.id);
        setInternalDragActiveRef.current(true);
        document.body.style.cursor = 'grabbing';

        // Create floating preview — small and semi-transparent so drop targets stay visible
        const preview = document.createElement('div');
        preview.style.cssText =
          'position:fixed;pointer-events:none;width:96px;border-radius:8px;overflow:hidden;box-shadow:0 8px 24px rgba(0,0,0,0.25);transform:rotate(2deg);z-index:99999;opacity:0.7;';
        const img = document.createElement('img');
        img.src =
          state.image.thumbnailUrl ||
          state.image.posterUrl ||
          state.image.url ||
          '';
        img.style.cssText = 'width:100%;height:auto;display:block;';
        img.draggable = false;
        preview.appendChild(img);
        document.body.appendChild(preview);
        state.previewEl = preview;
      }

      // Update preview position (offset so cursor is at top-left corner)
      if (state.previewEl) {
        state.previewEl.style.left = `${e.clientX + 12}px`;
        state.previewEl.style.top = `${e.clientY + 8}px`;
      }

      // Highlight space tabs on hover via data attribute (avoids React re-renders)
      // Skip the "All" tab (data-space-tab-id="") — all images are already there.
      const hoveredEl = document.elementFromPoint(e.clientX, e.clientY);
      let currentTabEl: HTMLElement | null = hoveredEl as HTMLElement;
      while (currentTabEl) {
        if (currentTabEl.dataset.spaceTabId !== undefined) {
          if (currentTabEl.dataset.spaceTabId === '') currentTabEl = null; // skip "All"
          break;
        }
        currentTabEl = currentTabEl.parentElement;
      }
      if (currentTabEl !== state.lastHighlightedTab) {
        state.lastHighlightedTab?.removeAttribute('data-drag-over');
        currentTabEl?.setAttribute('data-drag-over', 'true');
        state.lastHighlightedTab = currentTabEl;
      }

      // Near window edge → hand off to native OS drag for desktop export
      const margin = 20;
      const nearEdge =
        e.clientX < margin ||
        e.clientX > window.innerWidth - margin ||
        e.clientY > window.innerHeight - margin;
      // Don't trigger on top edge — space tabs live there

      if (nearEdge && state.isDragging && window.electron?.startDrag) {
        const image = state.image;
        const filePath =
          image.actualFilePath || image.url?.replace('local-file://', '');
        if (filePath) {
          state.nativeDragStarted = true;

          // Remove custom preview — OS will show its own
          if (state.previewEl) {
            state.previewEl.remove();
            state.previewEl = null;
          }
          if (state.lastHighlightedTab) {
            state.lastHighlightedTab.removeAttribute('data-drag-over');
            state.lastHighlightedTab = null;
          }
          document.body.style.cursor = '';

          const iconUrl = image.thumbnailUrl || image.posterUrl || '';
          const iconPath = iconUrl.replace('local-file://', '');
          const displayName =
            image.title ||
            image.imageContext?.substring(0, 60) ||
            undefined;
          window.electron.startDrag(filePath, iconPath, displayName);

          // Cleanup timer — native drag will complete eventually
          state.cleanupTimer = setTimeout(() => {
            cleanupDrag();
            justDraggedRef.current = false;
          }, 10000);
        }
      }

      if (state.isDragging) {
        e.preventDefault(); // prevent text selection
      }
    };

    const handleMouseUp = (e: MouseEvent) => {
      const state = customDragRef.current;
      if (!state) return;

      if (state.nativeDragStarted) return; // cleanup via timer

      if (state.isDragging) {
        // Check if released over a space tab (skip "All" tab)
        const el = document.elementFromPoint(e.clientX, e.clientY);
        let target: HTMLElement | null = el as HTMLElement;
        while (target) {
          if (target.dataset.spaceTabId !== undefined) {
            if (target.dataset.spaceTabId !== '') {
              onAssignToSpaceRef.current?.(state.image.id, target.dataset.spaceTabId);
            }
            break;
          }
          target = target.parentElement;
        }

        setTimeout(() => {
          justDraggedRef.current = false;
        }, 50);
      } else {
        justDraggedRef.current = false;
      }

      cleanupDrag();
    };

    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);
    return () => {
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    };
  }, []);

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
    <div className={`w-full px-4 pt-5 pb-4 flex-1 min-h-full flex flex-col bg-gray-100 dark:bg-zinc-900 ${images.length === 0 && !searchQuery && !activeSpaceId ? 'overflow-hidden' : ''}`}>
      {images.length === 0 ? (
        <div className="flex-1 flex items-stretch">
          {searchQuery ? (
            <div className="flex justify-center items-center w-full flex-1">
              <p className="text-sm text-muted-foreground select-none">
                Nothing found
              </p>
            </div>
          ) : isSpaceFilteredEmpty ? (
            <div className="flex justify-center items-center w-full flex-1">
              <p className="text-sm text-muted-foreground select-none">
                Drop images here or move existing images to this space
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

              {/* Centered card */}
              <div className="absolute top-0 left-0 right-0 bottom-0 flex items-center justify-center pointer-events-none z-[100]" style={{ paddingTop: "20px" }}>
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

                const isDragged = dragContext.draggedImageId === image.id;

                const imageCard = (
                  <div
                    ref={ref}
                    draggable={false}
                    onMouseDown={(e) => handleImageMouseDown(e, image)}
                    className="rounded-lg overflow-hidden bg-gray-100 dark:bg-zinc-800 shadow-sm hover:shadow-md relative group w-full transition-opacity duration-150"
                    onClick={() => handleImageClick(image, ref)}
                    onMouseEnter={() => setHoveredImageId(image.id)}
                    onMouseLeave={() => setHoveredImageId(null)}
                    style={{
                      opacity: isSelected ? 0 : (isDragged ? 0.4 : 1),
                      visibility: isSelected ? 'hidden' : 'visible',
                      pointerEvents: isAnimating ? 'none' : 'auto',
                      cursor: 'default',
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
                );

                return (
                  <div key={image.id} className="masonry-item">
                    {onAssignToSpace && spaces.length > 0 ? (
                      <ContextMenu>
                        <ContextMenuTrigger asChild>
                          {imageCard}
                        </ContextMenuTrigger>
                        <ContextMenuContent>
                          <ContextMenuSub>
                            <ContextMenuSubTrigger>Move to</ContextMenuSubTrigger>
                            <ContextMenuSubContent>
                              {spaces.map(space => (
                                <ContextMenuItem
                                  key={space.id}
                                  onClick={() => onAssignToSpace(image.id, space.id)}
                                  className={image.spaceId === space.id ? "font-medium" : ""}
                                >
                                  {space.name}
                                  {image.spaceId === space.id && (
                                    <span className="ml-auto text-xs text-gray-400">current</span>
                                  )}
                                </ContextMenuItem>
                              ))}
                            </ContextMenuSubContent>
                          </ContextMenuSub>
                          {image.spaceId && (
                            <>
                              <ContextMenuSeparator />
                              <ContextMenuItem onClick={() => onAssignToSpace(image.id, null)}>
                                Remove from Space
                              </ContextMenuItem>
                            </>
                          )}
                        </ContextMenuContent>
                      </ContextMenu>
                    ) : (
                      imageCard
                    )}
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
            initialRect={initialRect}
            patternElements={null}
            onAnimationComplete={handleAnimationComplete}
          />
        </>
      )}
    </div>
  );
};

export default ImageGrid;