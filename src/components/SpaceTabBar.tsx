import React, { useState, useRef, useEffect } from "react";
import { motion } from "framer-motion";
import { Plus } from "lucide-react";
import { Space } from "@/hooks/useSpaces";
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
}

export function SpaceTabBar({
  spaces,
  activeSpaceId,
  onSelectSpace,
  onCreateSpace,
  onRenameSpace,
  onDeleteSpace,
}: SpaceTabBarProps) {
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editValue, setEditValue] = useState("");
  const editInputRef = useRef<HTMLInputElement>(null);

  // Focus the input when entering edit mode
  useEffect(() => {
    if (editingId) {
      // Use rAF so the input is in the DOM before we focus
      const rafId = requestAnimationFrame(() => {
        editInputRef.current?.focus();
        editInputRef.current?.select();
      });
      return () => cancelAnimationFrame(rafId);
    }
  }, [editingId]);

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
    // Enter rename mode immediately
    setEditingId(space.id);
    setEditValue(space.name);
  };

  const tabs: { id: string | null; name: string }[] = [
    { id: null, name: "All" },
    ...spaces.map(s => ({ id: s.id, name: s.name })),
  ];

  return (
    <div className="px-6 flex items-center gap-1 border-b border-gray-200/50 dark:border-zinc-800/50 overflow-x-auto scrollbar-hide">
      {tabs.map((tab) => {
        const isActive = activeSpaceId === tab.id;
        const isSpace = tab.id !== null;
        const isEditing = isSpace && editingId === tab.id;

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
                  className="absolute bottom-0 left-3 right-3 h-0.5 bg-gray-900 dark:bg-gray-100 rounded-full"
                  transition={{ type: "spring", damping: 30, stiffness: 400 }}
                />
              )}
            </div>
          );
        }

        const tabButton = (
          <button
            key={tab.id ?? "all"}
            onClick={() => onSelectSpace(tab.id)}
            onDoubleClick={() => {
              if (isSpace) {
                const space = spaces.find(s => s.id === tab.id);
                if (space) startRename(space);
              }
            }}
            className="relative px-3 py-3 text-sm whitespace-nowrap transition-colors non-draggable focus:outline-none"
          >
            <span
              className={
                isActive
                  ? "font-medium text-gray-900 dark:text-gray-100"
                  : "text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300"
              }
            >
              {tab.name}
            </span>
            {isActive && (
              <motion.div
                layoutId="activeSpaceIndicator"
                className="absolute bottom-0 left-3 right-3 h-0.5 bg-gray-900 dark:bg-gray-100 rounded-full"
                transition={{ type: "spring", damping: 30, stiffness: 400 }}
              />
            )}
          </button>
        );

        // Wrap space tabs (not "All") in context menu
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
