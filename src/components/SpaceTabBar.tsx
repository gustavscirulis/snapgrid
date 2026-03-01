import React, { useState, useRef, useEffect, useCallback } from "react";
import { motion } from "framer-motion";
import { Plus } from "lucide-react";
import { Space } from "@/hooks/useSpaces";
import { useDragContext } from "./UploadZone";
import {
  ContextMenu,
  ContextMenuTrigger,
  ContextMenuContent,
  ContextMenuItem,
  ContextMenuSeparator,
} from "@/components/ui/context-menu";

interface SpaceTabBarProps {
  spaces: Space[];
  activeSpaceId: string | null;
  onSelectSpace: (id: string | null) => void;
  onCreateSpace: (name: string) => Promise<Space>;
  onRenameSpace: (id: string, name: string) => Promise<void>;
  onDeleteSpace: (id: string) => Promise<void>;
  onAssignToSpace?: (imageId: string, spaceId: string | null) => Promise<void>;
  onReorderSpaces?: (fromIndex: number, toIndex: number) => void;
}

export function SpaceTabBar({
  spaces,
  activeSpaceId,
  onSelectSpace,
  onCreateSpace,
  onRenameSpace,
  onDeleteSpace,
  onAssignToSpace,
  onReorderSpaces,
}: SpaceTabBarProps) {
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editValue, setEditValue] = useState("");
  const editInputRef = useRef<HTMLInputElement>(null);
  const [dragOverTabId, setDragOverTabId] = useState<string | null | undefined>(undefined);

  // Tab reorder drag state — transform-based (no array reordering during drag)
  const [reorderDragId, setReorderDragId] = useState<string | null>(null);
  const [dragTranslateX, setDragTranslateX] = useState(0);
  const [dragTargetIndex, setDragTargetIndex] = useState<number | null>(null);
  const dragTargetIndexRef = useRef<number | null>(null);
  const reorderDragRef = useRef<{
    spaceId: string;
    originalIndex: number;
    startX: number;
    isDragging: boolean;
    tabPositions: { left: number; midX: number; width: number }[];
    draggedWidth: number;
    gap: number;
  } | null>(null);
  const tabRefsMap = useRef<Map<string, HTMLElement>>(new Map());

  const dragContext = useDragContext();

  useEffect(() => {
    if (editingId) {
      const rafId = requestAnimationFrame(() => {
        editInputRef.current?.focus();
        editInputRef.current?.select();
      });
      return () => cancelAnimationFrame(rafId);
    }
  }, [editingId]);

  useEffect(() => {
    if (!dragContext.draggedImageId) {
      setDragOverTabId(undefined);
    }
  }, [dragContext.draggedImageId]);

  // Tab reorder: global mouse handlers
  useEffect(() => {
    const handleMouseMove = (e: MouseEvent) => {
      const state = reorderDragRef.current;
      if (!state) return;

      if (!state.isDragging) {
        const dx = e.clientX - state.startX;
        if (dx * dx < 25) return; // 5px threshold

        // Activate drag — snapshot all tab positions
        state.isDragging = true;
        const positions = spaces.map(s => {
          const el = tabRefsMap.current.get(s.id);
          if (!el) return { left: 0, midX: 0, width: 0 };
          const rect = el.getBoundingClientRect();
          return { left: rect.left, midX: rect.left + rect.width / 2, width: rect.width };
        });
        state.tabPositions = positions;
        state.draggedWidth = positions[state.originalIndex]?.width ?? 0;
        state.gap = positions.length >= 2
          ? Math.abs(positions[1].left - (positions[0].left + positions[0].width))
          : 4;

        setReorderDragId(state.spaceId);
        document.body.style.cursor = 'grabbing';
      }

      // Dragged tab follows cursor
      setDragTranslateX(e.clientX - state.startX);

      // Determine target index from original (snapshotted) midpoints
      let targetIndex = 0;
      for (let i = 0; i < state.tabPositions.length; i++) {
        if (e.clientX >= state.tabPositions[i].midX) {
          targetIndex = i;
        }
      }
      dragTargetIndexRef.current = targetIndex;
      setDragTargetIndex(targetIndex);
    };

    const handleMouseUp = () => {
      const state = reorderDragRef.current;
      if (!state) return;

      if (state.isDragging && onReorderSpaces) {
        const target = dragTargetIndexRef.current ?? state.originalIndex;
        if (target !== state.originalIndex) {
          onReorderSpaces(state.originalIndex, target);
        }
      }

      reorderDragRef.current = null;
      dragTargetIndexRef.current = null;
      setReorderDragId(null);
      setDragTranslateX(0);
      setDragTargetIndex(null);
      document.body.style.cursor = '';
    };

    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);
    return () => {
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    };
  }, [spaces, onReorderSpaces]);

  const handleTabMouseDown = useCallback((e: React.MouseEvent, spaceId: string, spaceIndex: number) => {
    if (e.button !== 0 || editingId) return;
    reorderDragRef.current = {
      spaceId,
      originalIndex: spaceIndex,
      startX: e.clientX,
      isDragging: false,
      tabPositions: [],
      draggedWidth: 0,
      gap: 4,
    };
  }, [editingId]);

  // Compute translateX for non-dragged tabs to shift out of the way
  const getTabShiftX = useCallback((spaceIndex: number): number => {
    if (dragTargetIndex === null || !reorderDragRef.current) return 0;
    const { originalIndex, draggedWidth, gap } = reorderDragRef.current;
    if (spaceIndex === originalIndex) return 0;

    const shiftAmount = draggedWidth + gap;

    if (originalIndex < dragTargetIndex) {
      // Moving right: tabs between original+1..target shift left
      if (spaceIndex > originalIndex && spaceIndex <= dragTargetIndex) {
        return -shiftAmount;
      }
    } else if (originalIndex > dragTargetIndex) {
      // Moving left: tabs between target..original-1 shift right
      if (spaceIndex >= dragTargetIndex && spaceIndex < originalIndex) {
        return shiftAmount;
      }
    }
    return 0;
  }, [dragTargetIndex]);

  const startRename = (space: Space) => {
    setEditingId(space.id);
    setEditValue(space.name);
  };

  const commitRename = () => {
    if (editingId && editValue.trim()) {
      onRenameSpace(editingId, editValue.trim());
    }
    setEditingId(null);
  };

  const handleCreate = async () => {
    const space = await onCreateSpace("New Space");
    onSelectSpace(space.id);
    setEditingId(space.id);
    setEditValue(space.name);
  };

  // Find the space tab ID from a drag event target by walking up the DOM
  const getTabIdFromEvent = useCallback((e: React.DragEvent): string | null | undefined => {
    let el = e.target as HTMLElement | null;
    while (el) {
      if (el.dataset.spaceTabId !== undefined) {
        return el.dataset.spaceTabId || null;
      }
      el = el.parentElement;
    }
    return undefined;
  }, []);

  const handleContainerDragOver = useCallback((e: React.DragEvent) => {
    const tabId = getTabIdFromEvent(e);
    if (tabId !== undefined) {
      e.preventDefault();
      e.stopPropagation();
      e.dataTransfer.dropEffect = 'move';
      setDragOverTabId(tabId);
    }
  }, [getTabIdFromEvent]);

  const handleContainerDragLeave = useCallback((e: React.DragEvent) => {
    const related = e.relatedTarget as HTMLElement | null;
    if (!related || !e.currentTarget.contains(related)) {
      setDragOverTabId(undefined);
    }
  }, []);

  const handleContainerDrop = useCallback((e: React.DragEvent) => {
    const tabId = getTabIdFromEvent(e);
    setDragOverTabId(undefined);

    if (tabId !== undefined) {
      e.preventDefault();
      e.stopPropagation();
      const imageId = e.dataTransfer.getData('application/x-snapgrid-image') || dragContext.draggedImageId;
      if (imageId && onAssignToSpace) {
        onAssignToSpace(imageId, tabId);
        dragContext.setDraggedImageId(null);
      }
    }
  }, [getTabIdFromEvent, dragContext.draggedImageId, onAssignToSpace]);

  const isReorderDragging = reorderDragId !== null;

  const tabs: { id: string | null; name: string }[] = [
    { id: null, name: "All" },
    ...spaces.map(s => ({ id: s.id, name: s.name })),
  ];

  const isDragActive = dragContext.draggedImageId !== null;

  return (
    <div
      className="px-6 flex items-center gap-1 border-b border-gray-200/50 dark:border-zinc-800/50 overflow-x-auto scrollbar-hide"
      onDragOver={handleContainerDragOver}
      onDragLeave={handleContainerDragLeave}
      onDrop={handleContainerDrop}
    >
      {tabs.map((tab, tabIndex) => {
        const isActive = activeSpaceId === tab.id;
        const isSpace = tab.id !== null;
        const isEditing = isSpace && editingId === tab.id;
        const isDropHighlighted = isDragActive && dragOverTabId === tab.id;
        const isBeingDragged = isReorderDragging && reorderDragId === tab.id;
        const spaceIndex = isSpace ? tabIndex - 1 : -1;

        // When editing, render a standalone input instead of the button
        if (isEditing) {
          return (
            <div key={tab.id} className="relative px-3 py-3 text-sm whitespace-nowrap non-draggable">
              <input
                ref={editInputRef}
                value={editValue}
                onChange={(e) => setEditValue(e.target.value)}
                onBlur={commitRename}
                onKeyDown={(e) => {
                  if (e.key === "Enter") commitRename();
                  if (e.key === "Escape") setEditingId(null);
                }}
                className="bg-transparent border-none outline-none text-sm font-medium text-gray-900 dark:text-gray-100 w-24 min-w-0"
              />
              {isActive && (
                <motion.div
                  layoutId="activeSpaceIndicator"
                  className="absolute bottom-0 left-3 right-3 h-0.5 bg-gray-900 dark:bg-gray-100 rounded-full z-20"
                  transition={{ type: "spring", damping: 30, stiffness: 400 }}
                />
              )}
            </div>
          );
        }

        const tabButton = (
          <button
            ref={isSpace ? (el: HTMLButtonElement | null) => {
              if (el) tabRefsMap.current.set(tab.id!, el);
              else tabRefsMap.current.delete(tab.id!);
            } : undefined}
            data-space-tab-id={tab.id ?? ""}
            onMouseDown={isSpace ? (e: React.MouseEvent) => handleTabMouseDown(e, tab.id!, spaceIndex) : undefined}
            onClick={() => {
              if (reorderDragRef.current?.isDragging) return;
              onSelectSpace(tab.id);
            }}
            onDoubleClick={() => {
              if (isSpace) {
                const space = spaces.find(s => s.id === tab.id);
                if (space) startRename(space);
              }
            }}
            className={`relative px-3 py-3 text-sm whitespace-nowrap transition-colors duration-150 non-draggable outline-none focus:outline-none ${
              isDropHighlighted ? 'bg-black/[0.04] dark:bg-white/[0.06] rounded-md' : ''
            }`}
          >
            <span
              className={
                isDropHighlighted
                  ? "font-medium text-gray-600 dark:text-gray-300"
                  : isActive
                    ? "font-medium text-gray-900 dark:text-gray-100"
                    : "text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300"
              }
            >
              {tab.name}
            </span>
            {isActive && (
              <motion.div
                layoutId="activeSpaceIndicator"
                className="absolute bottom-0 left-3 right-3 h-0.5 bg-gray-900 dark:bg-gray-100 rounded-full z-20"
                transition={{ type: "spring", damping: 30, stiffness: 400 }}
              />
            )}
          </button>
        );

        if (isSpace) {
          // Compute transform: dragged tab follows cursor, others shift aside
          const xOffset = isBeingDragged ? dragTranslateX : getTabShiftX(spaceIndex);

          return (
            <motion.div key={tab.id}
              animate={{
                x: xOffset,
                scale: isBeingDragged ? 1.05 : 1,
                boxShadow: isBeingDragged
                  ? '0 4px 12px rgba(0,0,0,0.12)'
                  : '0 0px 0px rgba(0,0,0,0)',
              }}
              transition={{
                x: isBeingDragged
                  ? { duration: 0 }
                  : isReorderDragging
                    ? { type: "spring", damping: 30, stiffness: 400 }
                    : { duration: 0 },
                scale: { type: "spring", damping: 30, stiffness: 400 },
                boxShadow: { type: "spring", damping: 30, stiffness: 400 },
              }}
              style={{
                zIndex: isBeingDragged ? 10 : undefined,
                position: 'relative',
              }}
            >
              <ContextMenu>
                <ContextMenuTrigger asChild>{tabButton}</ContextMenuTrigger>
                <ContextMenuContent>
                  <ContextMenuItem onClick={() => startRename(spaces.find(s => s.id === tab.id)!)}>
                    Rename
                  </ContextMenuItem>
                  <ContextMenuSeparator />
                  <ContextMenuItem
                    onClick={() => onDeleteSpace(tab.id!)}
                    className="text-red-600 dark:text-red-400 focus:text-red-600 dark:focus:text-red-400"
                  >
                    Delete
                  </ContextMenuItem>
                </ContextMenuContent>
              </ContextMenu>
            </motion.div>
          );
        }

        return tabButton;
      })}

      <button
        onClick={handleCreate}
        className="px-2 py-3 text-gray-400 dark:text-gray-500 hover:text-gray-600 dark:hover:text-gray-300 transition-colors non-draggable flex-shrink-0 focus:outline-none"
        title="New Space"
      >
        <Plus className="h-4 w-4" />
      </button>
    </div>
  );
}
