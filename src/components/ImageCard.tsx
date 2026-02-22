import React, { useState, useCallback } from "react";
import { ImageItem } from "@/hooks/useImageStore";
import { ImageRenderer } from "@/components/ImageRenderer";
import { motion, AnimatePresence } from "framer-motion";
import PatternTags from "./PatternTags";
import { X, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Space } from "@/hooks/useSpaces";
import { useImagePreloader } from "@/hooks/useImagePreloader";
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

interface ImageCardProps {
  image: ImageItem;
  imageRef: React.RefObject<HTMLDivElement>;
  isModalTarget: boolean;
  isDragged: boolean;
  isAnimating: boolean;
  isMultiSelected: boolean;
  selectionCount: number;
  preloader: ReturnType<typeof useImagePreloader>;
  retryAnalysis?: (imageId: string) => Promise<void>;
  activeSpaceId?: string | null;
  spaces: Space[];
  onImageClick: (image: ImageItem, ref: React.RefObject<HTMLDivElement>) => void;
  onImageDelete?: (id: string) => void;
  onMouseDown: (e: React.MouseEvent, image: ImageItem) => void;
  onCmdClick?: (id: string) => void;
  onShiftClick?: (id: string) => void;
  onAssignToSpace?: (imageId: string, spaceId: string | null) => Promise<void>;
  onBulkAssignToSpace?: (spaceId: string | null) => Promise<void>;
  onBulkDelete?: () => void;
  onRemoveFromSpace?: (imageId: string) => void;
  onBulkRemoveFromSpace?: () => void;
}

const ImageCard = React.memo<ImageCardProps>(function ImageCard({
  image,
  imageRef,
  isModalTarget,
  isDragged,
  isAnimating,
  isMultiSelected,
  selectionCount,
  preloader,
  retryAnalysis,
  activeSpaceId,
  spaces,
  onImageClick,
  onImageDelete,
  onMouseDown,
  onCmdClick,
  onShiftClick,
  onAssignToSpace,
  onBulkAssignToSpace,
  onBulkDelete,
  onRemoveFromSpace,
  onBulkRemoveFromSpace,
}) {
  // Hover state is LOCAL to each card — no parent re-renders
  const [isHovered, setIsHovered] = useState(false);

  const handleClick = useCallback((e: React.MouseEvent) => {
    if (e.metaKey || e.ctrlKey) {
      e.stopPropagation();
      onCmdClick?.(image.id);
      return;
    }
    if (e.shiftKey) {
      e.stopPropagation();
      onShiftClick?.(image.id);
      return;
    }
    onImageClick(image, imageRef);
  }, [image, imageRef, onImageClick, onCmdClick, onShiftClick]);

  const handleMouseDown = useCallback((e: React.MouseEvent) => {
    onMouseDown(e, image);
  }, [image, onMouseDown]);

  const showBulkMenu = isMultiSelected && selectionCount > 1;

  const cardContent = (
    <div
      ref={imageRef}
      draggable={false}
      onMouseDown={handleMouseDown}
      className={`rounded-lg overflow-hidden bg-gray-100 dark:bg-zinc-800 shadow-sm hover:shadow-md relative group w-full transition-all duration-150 ${
        isMultiSelected ? 'ring-2 ring-blue-500 ring-offset-1 ring-offset-gray-100 dark:ring-offset-zinc-900' : ''
      }`}
      onClick={handleClick}
      onMouseEnter={() => setIsHovered(true)}
      onMouseLeave={() => setIsHovered(false)}
      style={{
        opacity: isModalTarget ? 0 : (isDragged ? 0.4 : 1),
        visibility: isModalTarget ? 'hidden' : 'visible',
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
          {isHovered && !isMultiSelected && (
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
          <div className="absolute bottom-2 right-2 bg-black/70 p-1 rounded text-white text-xs">
            <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 20 20" xmlns="http://www.w3.org/2000/svg">
              <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM9.555 7.168A1 1 0 008 8v4a1 1 0 001.555.832l3-2a1 1 0 000-1.664l-3-2z" clipRule="evenodd"></path>
            </svg>
          </div>
        )}

        <div className="absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity flex gap-1.5">
          {activeSpaceId && onRemoveFromSpace && (
            <Button
              variant="ghost"
              size="icon"
              className="p-1 rounded-full h-6 w-6 bg-black/60 text-white hover:text-white hover:bg-black/80"
              onClick={(e) => {
                e.stopPropagation();
                onRemoveFromSpace(image.id);
              }}
              title="Remove from space"
            >
              <X className="h-3 w-3" />
            </Button>
          )}
          {onImageDelete && (
            <Button
              variant="ghost"
              size="icon"
              className="p-1 rounded-full h-6 w-6 bg-black/60 text-white hover:text-white hover:bg-red-600/90"
              onClick={(e) => {
                e.stopPropagation();
                onImageDelete(image.id);
              }}
              title="Delete"
            >
              <Trash2 className="h-3 w-3" />
            </Button>
          )}
        </div>
      </div>
    </div>
  );

  // Determine which context menu to show
  const hasSpaces = spaces.length > 0;
  const needsContextMenu = hasSpaces && (onAssignToSpace || showBulkMenu);

  if (needsContextMenu) {
    return (
      <div className="masonry-item">
        <ContextMenu>
          <ContextMenuTrigger asChild>
            {cardContent}
          </ContextMenuTrigger>
          <ContextMenuContent>
            {showBulkMenu ? (
              // Bulk context menu for multi-selection
              <>
                {onBulkAssignToSpace && (
                  <ContextMenuSub>
                    <ContextMenuSubTrigger>Move {selectionCount} items to</ContextMenuSubTrigger>
                    <ContextMenuSubContent>
                      {spaces.map(space => (
                        <ContextMenuItem
                          key={space.id}
                          onClick={() => onBulkAssignToSpace(space.id)}
                        >
                          {space.name}
                        </ContextMenuItem>
                      ))}
                    </ContextMenuSubContent>
                  </ContextMenuSub>
                )}
                {activeSpaceId && onBulkRemoveFromSpace && (
                  <>
                    <ContextMenuSeparator />
                    <ContextMenuItem onClick={onBulkRemoveFromSpace}>
                      Remove {selectionCount} items from Space
                    </ContextMenuItem>
                  </>
                )}
                {onBulkDelete && (
                  <>
                    <ContextMenuSeparator />
                    <ContextMenuItem
                      onClick={onBulkDelete}
                      className="text-red-600 dark:text-red-400"
                    >
                      Delete {selectionCount} items
                    </ContextMenuItem>
                  </>
                )}
              </>
            ) : (
              // Single-item context menu
              <>
                {onAssignToSpace && (
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
                )}
                {activeSpaceId && image.spaceId && onAssignToSpace && (
                  <>
                    <ContextMenuSeparator />
                    <ContextMenuItem onClick={() => onAssignToSpace(image.id, null)}>
                      Remove from Space
                    </ContextMenuItem>
                  </>
                )}
              </>
            )}
          </ContextMenuContent>
        </ContextMenu>
      </div>
    );
  }

  return <div className="masonry-item">{cardContent}</div>;
});

export default ImageCard;
