import { useEffect } from 'react';

interface KeyboardShortcutsProps {
  onUndo: () => void;
  onFocusSearch: () => void;
  onUnfocusSearch: () => void;
  onOpenSettings?: () => void;
  onZoomIn?: () => void;
  onZoomOut?: () => void;
  onSwitchSpace?: (index: number) => void;
  onSelectAll?: () => void;
  onDeleteSelected?: () => void;
  onClearSelection?: () => boolean;
}

export function useKeyboardShortcuts({
  onUndo,
  onFocusSearch,
  onUnfocusSearch,
  onOpenSettings,
  onZoomIn,
  onZoomOut,
  onSwitchSpace,
  onSelectAll,
  onDeleteSelected,
  onClearSelection
}: KeyboardShortcutsProps) {
  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      const isInputFocused = ['INPUT', 'TEXTAREA'].includes((event.target as HTMLElement).tagName);

      // Check for Command+Z (Mac) or Ctrl+Z (Windows/Linux)
      if ((event.metaKey || event.ctrlKey) && event.key === 'z') {
        event.preventDefault(); // Prevent default browser undo behavior
        onUndo();
      }

      // Check for Command+F or Command+K to focus search
      if (
        (event.metaKey || event.ctrlKey) && (event.key === 'f' || event.key === 'k')
      ) {
        event.preventDefault(); // Prevent default browser search behavior
        onFocusSearch();
      }

      // Check for Command+comma to open settings (Mac standard)
      if ((event.metaKey || event.ctrlKey) && event.key === ',') {
        event.preventDefault();
        onOpenSettings?.();
      }

      // Escape: clear selection first, then unfocus search
      if (event.key === 'Escape') {
        if (onClearSelection?.()) {
          // Selection was non-empty and was cleared — stop here
          return;
        }
        onUnfocusSearch();
      }

      // Check for Command+Plus (Cmd+=) or Command+Minus (Cmd+-) for thumbnail sizing
      if ((event.metaKey || event.ctrlKey) && (event.key === '=' || event.key === '+')) {
        event.preventDefault(); // Prevent default browser zoom behavior
        onZoomIn?.();
      }

      if ((event.metaKey || event.ctrlKey) && event.key === '-') {
        event.preventDefault(); // Prevent default browser zoom behavior
        onZoomOut?.();
      }

      // Cmd+1-9 to switch spaces (1 = All, 2 = first space, etc.)
      if ((event.metaKey || event.ctrlKey) && event.key >= '1' && event.key <= '9') {
        event.preventDefault();
        onSwitchSpace?.(parseInt(event.key, 10));
      }

      // Cmd+A: Select all (only when not in input)
      if ((event.metaKey || event.ctrlKey) && event.key === 'a' && !isInputFocused) {
        event.preventDefault();
        onSelectAll?.();
      }

      // Delete/Backspace: Delete selected (only when not in input)
      if ((event.key === 'Delete' || event.key === 'Backspace') && !isInputFocused) {
        event.preventDefault();
        onDeleteSelected?.();
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [onUndo, onFocusSearch, onUnfocusSearch, onOpenSettings, onZoomIn, onZoomOut, onSwitchSpace, onSelectAll, onDeleteSelected, onClearSelection]);
}
