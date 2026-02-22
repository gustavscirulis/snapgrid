import React, { useState, useEffect, useRef, useCallback, useMemo, useImperativeHandle, forwardRef } from "react";
import { createPortal } from "react-dom";
import { ImageItem } from "@/hooks/useImageStore";
import AnimatedImageModal from "./AnimatedImageModal";
import { motion, AnimatePresence } from "framer-motion";
import Masonry from 'react-masonry-css';
import './masonry-grid.css';
import './text-shine.css';
import { useDragContext } from "./UploadZone";
import { useImagePreloader } from "@/hooks/useImagePreloader";
import { useApiKeyWatcher } from "@/hooks/useApiKeyWatcher";
import EmptyStateCard from "./EmptyStateCard";
import EmptyStatePlaceholders from "./EmptyStatePlaceholders";
import { Space } from "@/hooks/useSpaces";
import ImageCard from "./ImageCard";
import { useSelection } from "@/hooks/useSelection";
import { useRubberBand } from "@/hooks/useRubberBand";

export interface ImageGridHandle {
  selectAll: () => void;
  clearSelection: () => boolean;
  deleteSelected: () => void;
}

interface ImageGridProps {
  images: ImageItem[];
  onImageClick: (image: ImageItem) => void;
  onImageDelete?: (id: string) => void;
  onImagesDelete?: (ids: string[]) => void;
  searchQuery?: string;
  onOpenSettings?: () => void;
  settingsOpen?: boolean;
  retryAnalysis?: (imageId: string) => Promise<void>;
  thumbnailSize?: 'small' | 'medium' | 'large' | 'xl';
  spaces?: Space[];
  activeSpaceId?: string | null;
  onAssignToSpace?: (imageId: string, spaceId: string | null) => Promise<void>;
  onAssignImagesToSpace?: (imageIds: string[], spaceId: string | null) => Promise<void>;
  onRemoveFromSpace?: (imageId: string) => void;
  scrollContainerRef?: React.RefObject<HTMLElement>;
}

const ImageGrid = forwardRef<ImageGridHandle, ImageGridProps>(function ImageGrid(
  { images, onImageClick, onImageDelete, onImagesDelete, searchQuery = "", onOpenSettings, settingsOpen = false, retryAnalysis, thumbnailSize = 'medium', spaces = [], activeSpaceId, onAssignToSpace, onAssignImagesToSpace, onRemoveFromSpace, scrollContainerRef },
  ref
) {
  const [selectedImage, setSelectedImage] = useState<ImageItem | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [selectedImageRef, setSelectedImageRef] = useState<React.RefObject<HTMLDivElement> | null>(null);
  const [initialRect, setInitialRect] = useState<{ top: number; left: number; width: number; height: number } | null>(null);
  const [clickedImageId, setClickedImageId] = useState<string | null>(null);
  const [exitAnimationComplete, setExitAnimationComplete] = useState(false);
  const [isAnimating, setIsAnimating] = useState(false);
  const [activeDragIds, setActiveDragIds] = useState<Set<string>>(new Set());

  // Image refs for animations
  const imageRefs = useRef<Map<string, React.RefObject<HTMLDivElement>>>(new Map());

  // Selection state
  const selection = useSelection();

  // Ordered image IDs for range select and rubber band
  const orderedImageIds = useMemo(() => images.map(img => img.id), [images]);

  // Prune selection when images list changes (e.g. from search filter)
  useEffect(() => {
    const visibleIds = new Set(orderedImageIds);
    const currentSelection = selection.selectedIds;
    if (currentSelection.size === 0) return;
    let changed = false;
    for (const id of currentSelection) {
      if (!visibleIds.has(id)) {
        changed = true;
        break;
      }
    }
    if (changed) {
      const pruned = new Set<string>();
      for (const id of currentSelection) {
        if (visibleIds.has(id)) pruned.add(id);
      }
      selection.setSelection(pruned);
    }
  }, [orderedImageIds]); // eslint-disable-line react-hooks/exhaustive-deps

  // Default scroll container ref if none provided
  const fallbackScrollRef = useRef<HTMLElement>(null);
  const effectiveScrollRef = scrollContainerRef || fallbackScrollRef;

  // Rubber band selection
  const rubberBand = useRubberBand({
    scrollContainerRef: effectiveScrollRef,
    imageRefs,
    imageIds: orderedImageIds,
    onSelectionChange: selection.setSelection,
    existingSelection: selection.selectedIds,
  });

  // Expose methods to parent via ref
  useImperativeHandle(ref, () => ({
    selectAll: () => {
      selection.selectAll(orderedImageIds);
    },
    clearSelection: () => {
      return selection.clear();
    },
    deleteSelected: () => {
      if (selection.selectionCount === 0) return;
      const ids = Array.from(selection.selectedIds);
      if (onImagesDelete) {
        onImagesDelete(ids);
      } else if (onImageDelete) {
        ids.forEach(id => onImageDelete(id));
      }
      selection.clear();
    },
  }), [selection, orderedImageIds, onImagesDelete, onImageDelete]);

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
  const breakpointColumnsObj = useMemo(() => {
    switch (thumbnailSize) {
      case 'small':
        return { default: 6, 1536: 6, 1280: 5, 1024: 4, 640: 3, 480: 2 };
      case 'medium':
        return { default: 4, 1536: 4, 1280: 3, 1024: 2, 640: 1, 480: 1 };
      case 'large':
        return { default: 3, 1536: 3, 1280: 2, 1024: 2, 640: 1, 480: 1 };
      case 'xl':
        return { default: 2, 1536: 2, 1280: 2, 1024: 1, 640: 1, 480: 1 };
      default:
        return { default: 4, 1536: 4, 1280: 3, 1024: 2, 640: 1, 480: 1 };
    }
  }, [thumbnailSize]);

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

  // Use ref for isAnimating so handleImageClick doesn't need it as a dependency
  const isAnimatingRef = useRef(isAnimating);
  isAnimatingRef.current = isAnimating;

  const handleImageClick = useCallback((image: ImageItem, ref: React.RefObject<HTMLDivElement>) => {
    if (isAnimatingRef.current || justDraggedRef.current) return;

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
  }, [onImageClick]);

  const handleAnimationComplete = useCallback((definition: string) => {
    if (definition === "exit") {
      setExitAnimationComplete(true);
      setIsAnimating(false);
      setClickedImageId(null);
    }
  }, []);

  const closeModal = useCallback(() => {
    setModalOpen(false);
    // Don't reset clickedImageId here - wait for animation to complete
    // The thumbnail should stay hidden until handleAnimationComplete is called
  }, []);

  const handleDeleteImage = useCallback((id: string) => {
    onImageDelete?.(id);
  }, [onImageDelete]);

  // Selection click handlers
  const handleCmdClick = useCallback((id: string) => {
    selection.toggle(id);
  }, [selection]);

  const handleShiftClick = useCallback((id: string) => {
    selection.rangeSelect(id, orderedImageIds);
  }, [selection, orderedImageIds]);

  // Bulk action handlers
  const handleBulkAssignToSpace = useCallback(async (spaceId: string | null) => {
    if (selection.selectionCount === 0) return;
    const ids = Array.from(selection.selectedIds);
    if (onAssignImagesToSpace) {
      await onAssignImagesToSpace(ids, spaceId);
    } else if (onAssignToSpace) {
      await Promise.all(ids.map(id => onAssignToSpace(id, spaceId)));
    }
    selection.clear();
  }, [selection, onAssignImagesToSpace, onAssignToSpace]);

  const handleBulkDelete = useCallback(() => {
    if (selection.selectionCount === 0) return;
    const ids = Array.from(selection.selectedIds);
    if (onImagesDelete) {
      onImagesDelete(ids);
    } else if (onImageDelete) {
      ids.forEach(id => onImageDelete(id));
    }
    selection.clear();
  }, [selection, onImagesDelete, onImageDelete]);

  const handleBulkRemoveFromSpace = useCallback(async () => {
    if (selection.selectionCount === 0) return;
    const ids = Array.from(selection.selectedIds);
    if (onAssignImagesToSpace) {
      await onAssignImagesToSpace(ids, null);
    } else if (onAssignToSpace) {
      await Promise.all(ids.map(id => onAssignToSpace(id, null)));
    }
    selection.clear();
  }, [selection, onAssignImagesToSpace, onAssignToSpace]);

  // Custom mouse-based drag system for drag-to-space and drag-out-of-app.
  // We avoid HTML5 drag because Electron's startDrag (needed for desktop export)
  // is incompatible with it — startDrag takes over and fires dragend immediately.
  const customDragRef = useRef<{
    image: ImageItem;
    isMultiDrag: boolean;
    draggedIds: string[];
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
  const onAssignImagesToSpaceRef = useRef(onAssignImagesToSpace);
  onAssignImagesToSpaceRef.current = onAssignImagesToSpace;
  const setDraggedImageIdRef = useRef(dragContext.setDraggedImageId);
  setDraggedImageIdRef.current = dragContext.setDraggedImageId;
  const setInternalDragActiveRef = useRef(dragContext.setInternalDragActive);
  setInternalDragActiveRef.current = dragContext.setInternalDragActive;
  const selectionRef = useRef(selection);
  selectionRef.current = selection;
  const imagesRef = useRef(images);
  imagesRef.current = images;
  const setActiveDragIdsRef = useRef(setActiveDragIds);
  setActiveDragIdsRef.current = setActiveDragIds;

  const handleImageMouseDown = useCallback((e: React.MouseEvent, image: ImageItem) => {
    if (e.button !== 0) return;
    if ((e.target as HTMLElement).closest('button, input, a, [role="menuitem"]')) return;

    // Determine if this is a multi-drag
    const sel = selectionRef.current;
    const isMultiDrag = sel.selectedIds.has(image.id) && sel.selectionCount > 1;
    const draggedIds = isMultiDrag ? Array.from(sel.selectedIds) : [image.id];

    customDragRef.current = {
      image,
      isMultiDrag,
      draggedIds,
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
        setActiveDragIdsRef.current(new Set());
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
        setActiveDragIdsRef.current(new Set(state.draggedIds));
        document.body.style.cursor = 'grabbing';

        if (state.isMultiDrag) {
          // Create stacked preview for multi-drag
          const preview = document.createElement('div');
          preview.style.cssText =
            'position:fixed;pointer-events:none;z-index:99999;width:96px;height:96px;';

          const selectedImages = imagesRef.current.filter(img => state.draggedIds.includes(img.id));
          const stackImages = selectedImages.slice(0, 3);
          stackImages.forEach((img, i) => {
            const el = document.createElement('img');
            el.src = img.thumbnailUrl || img.posterUrl || img.url || '';
            el.style.cssText = `width:80px;border-radius:6px;display:block;position:absolute;box-shadow:0 4px 12px rgba(0,0,0,0.2);transform:rotate(${(i - 1) * 3}deg) translateY(${i * -4}px);opacity:${1 - i * 0.15};`;
            el.draggable = false;
            preview.appendChild(el);
          });

          // Count badge
          const badge = document.createElement('div');
          badge.textContent = `${state.draggedIds.length}`;
          badge.style.cssText = 'position:absolute;top:-8px;right:-8px;background:#3b82f6;color:white;border-radius:50%;min-width:20px;height:20px;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:600;padding:0 4px;';
          preview.appendChild(badge);

          document.body.appendChild(preview);
          state.previewEl = preview;
        } else {
          // Single image preview (existing behavior)
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
        if (state.isMultiDrag && window.electron?.startDragMultiple) {
          // Multi-file native drag
          const filePaths = state.draggedIds.map(id => {
            const img = imagesRef.current.find(i => i.id === id);
            return img?.actualFilePath || img?.url?.replace('local-file://', '') || '';
          }).filter(Boolean);

          if (filePaths.length > 0) {
            state.nativeDragStarted = true;
            if (state.previewEl) { state.previewEl.remove(); state.previewEl = null; }
            if (state.lastHighlightedTab) { state.lastHighlightedTab.removeAttribute('data-drag-over'); state.lastHighlightedTab = null; }
            document.body.style.cursor = '';

            const iconUrl = state.image.thumbnailUrl || state.image.posterUrl || '';
            const iconPath = iconUrl.replace('local-file://', '');
            window.electron.startDragMultiple(filePaths, iconPath);

            state.cleanupTimer = setTimeout(() => { cleanupDrag(); justDraggedRef.current = false; }, 10000);
          }
        } else {
          // Single file native drag (existing behavior)
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
              const spaceId = target.dataset.spaceTabId;
              if (state.isMultiDrag && onAssignImagesToSpaceRef.current) {
                onAssignImagesToSpaceRef.current(state.draggedIds, spaceId);
              } else {
                onAssignToSpaceRef.current?.(state.image.id, spaceId);
              }
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
    <div
      className={`w-full px-4 pt-5 pb-4 flex-1 min-h-full flex flex-col bg-gray-100 dark:bg-zinc-900 ${images.length === 0 && !searchQuery && !activeSpaceId ? 'overflow-hidden' : ''}`}
      onMouseDown={rubberBand.handleMouseDown}
    >
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

                return (
                  <ImageCard
                    key={image.id}
                    image={image}
                    imageRef={ref}
                    isModalTarget={clickedImageId === image.id}
                    isDragged={activeDragIds.has(image.id) || dragContext.draggedImageId === image.id}
                    isAnimating={isAnimating}
                    isMultiSelected={selection.selectedIds.has(image.id)}
                    selectionCount={selection.selectionCount}
                    preloader={preloader}
                    retryAnalysis={retryAnalysis}
                    activeSpaceId={activeSpaceId}
                    spaces={spaces}
                    onImageClick={handleImageClick}
                    onImageDelete={handleDeleteImage}
                    onMouseDown={handleImageMouseDown}
                    onCmdClick={handleCmdClick}
                    onShiftClick={handleShiftClick}
                    onAssignToSpace={onAssignToSpace}
                    onBulkAssignToSpace={handleBulkAssignToSpace}
                    onBulkDelete={handleBulkDelete}
                    onRemoveFromSpace={onRemoveFromSpace}
                    onBulkRemoveFromSpace={handleBulkRemoveFromSpace}
                  />
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

      {/* Rubber band selection rectangle — portal to escape carousel transform */}
      {rubberBand.isActive && rubberBand.rect && createPortal(
        <div
          className="fixed pointer-events-none border border-blue-400 bg-blue-400/10 z-50 rounded-sm"
          style={{
            left: rubberBand.rect.x,
            top: rubberBand.rect.y,
            width: rubberBand.rect.width,
            height: rubberBand.rect.height,
          }}
        />,
        document.body
      )}

      {/* Selection count indicator — portal to escape carousel transform */}
      {selection.selectionCount > 0 && createPortal(
        <div className="fixed bottom-6 left-1/2 -translate-x-1/2 z-50 bg-blue-500 text-white px-4 py-2 rounded-full text-sm font-medium shadow-lg select-none">
          {selection.selectionCount} selected
        </div>,
        document.body
      )}
    </div>
  );
});

export default ImageGrid;
