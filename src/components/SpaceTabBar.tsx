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
}

export function SpaceTabBar({
  spaces,
  activeSpaceId,
  onSelectSpace,
  onCreateSpace,
  onRenameSpace,
  onDeleteSpace,
  onAssignToSpace,
}: SpaceTabBarProps) {
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editValue, setEditValue] = useState("");
  const editInputRef = useRef<HTMLInputElement>(null);
  const [dragOverTabId, setDragOverTabId] = useState<string | null | undefined>(undefined);

  const dragContext = useDragContext();

  useEffect(() => {
    if (editingId && editInputRef.current) {
      editInputRef.current.focus();
      editInputRef.current.select();
    }
  }, [editingId]);

  useEffect(() => {
    if (!dragContext.draggedImageId) {
      setDragOverTabId(undefined);
    }
  }, [dragContext.draggedImageId]);

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
        // data-space-tab-id="" means the "All" tab (null)
        return el.dataset.spaceTabId || null;
      }
      el = el.parentElement;
    }
    return undefined; // not over any tab
  }, []);

  // Container-level drag handlers — more reliable than per-button handlers
  // because Radix ContextMenu's asChild can interfere with button-level drag events
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
    // Only clear if we're actually leaving the container
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
        // Clear drag state after successful assignment
        dragContext.setDraggedImageId(null);
      }
    }
  }, [getTabIdFromEvent, dragContext.draggedImageId, onAssignToSpace]);

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
      {tabs.map((tab) => {
        const isActive = activeSpaceId === tab.id;
        const isSpace = tab.id !== null;
        const isEditing = isSpace && editingId === tab.id;
        const isDropHighlighted = isDragActive && dragOverTabId === tab.id;

        const tabButton = (
          <button
            key={tab.id ?? "all"}
            data-space-tab-id={tab.id ?? ""}
            onClick={() => onSelectSpace(tab.id)}
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
            {isEditing ? (
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
                onClick={(e) => e.stopPropagation()}
              />
            ) : (
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
            )}
            {isActive && (
              <motion.div
                layoutId="activeSpaceIndicator"
                className="absolute bottom-0 left-3 right-3 h-0.5 bg-gray-900 dark:bg-gray-100 rounded-full"
                transition={{ type: "spring", damping: 30, stiffness: 400 }}
              />
            )}
          </button>
        );

        if (isSpace) {
          return (
            <ContextMenu key={tab.id}>
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
