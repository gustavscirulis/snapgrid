import { useState, useCallback, useRef } from "react";

export interface UseSelectionReturn {
  selectedIds: Set<string>;
  anchorId: string | null;
  isSelected: (id: string) => boolean;
  toggle: (id: string) => void;
  rangeSelect: (id: string, orderedIds: string[]) => void;
  selectAll: (ids: string[]) => void;
  clear: () => boolean;
  setSelection: (ids: Set<string>) => void;
  selectionCount: number;
}

export function useSelection(): UseSelectionReturn {
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [anchorId, setAnchorId] = useState<string | null>(null);

  // Ref for stable isSelected checks in memoized children
  const selectedIdsRef = useRef(selectedIds);
  selectedIdsRef.current = selectedIds;

  const isSelected = useCallback((id: string) => {
    return selectedIdsRef.current.has(id);
  }, []);

  const toggle = useCallback((id: string) => {
    setSelectedIds(prev => {
      const next = new Set(prev);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return next;
    });
    setAnchorId(id);
  }, []);

  const rangeSelect = useCallback((targetId: string, orderedIds: string[]) => {
    setSelectedIds(prev => {
      const anchor = anchorId;
      if (!anchor) {
        // No anchor — just select the target
        return new Set([targetId]);
      }

      const anchorIndex = orderedIds.indexOf(anchor);
      const targetIndex = orderedIds.indexOf(targetId);
      if (anchorIndex === -1 || targetIndex === -1) {
        return new Set([targetId]);
      }

      const start = Math.min(anchorIndex, targetIndex);
      const end = Math.max(anchorIndex, targetIndex);
      const rangeIds = orderedIds.slice(start, end + 1);

      // Merge with existing selection
      const next = new Set(prev);
      for (const id of rangeIds) {
        next.add(id);
      }
      return next;
    });
    // Don't update anchor on range select — anchor stays where it was
  }, [anchorId]);

  const selectAll = useCallback((ids: string[]) => {
    setSelectedIds(new Set(ids));
    if (ids.length > 0) {
      setAnchorId(ids[0]);
    }
  }, []);

  const clear = useCallback((): boolean => {
    if (selectedIdsRef.current.size === 0) return false;
    setSelectedIds(new Set());
    setAnchorId(null);
    return true;
  }, []);

  const setSelection = useCallback((ids: Set<string>) => {
    setSelectedIds(ids);
  }, []);

  return {
    selectedIds,
    anchorId,
    isSelected,
    toggle,
    rangeSelect,
    selectAll,
    clear,
    setSelection,
    selectionCount: selectedIds.size,
  };
}
