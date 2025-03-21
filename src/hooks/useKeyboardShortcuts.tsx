import { useEffect } from 'react';

interface KeyboardShortcutsProps {
  onUndo: () => void;
  onFocusSearch: () => void;
  onUnfocusSearch: () => void;
}

export function useKeyboardShortcuts({ onUndo, onFocusSearch, onUnfocusSearch }: KeyboardShortcutsProps) {
  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      // Check for Command+Z (Mac) or Ctrl+Z (Windows/Linux)
      if ((event.metaKey || event.ctrlKey) && event.key === 'z') {
        event.preventDefault(); // Prevent default browser undo behavior
        onUndo();
      }

      // Check for Command+F, Command+K, or "/" to focus search
      if (
        ((event.metaKey || event.ctrlKey) && (event.key === 'f' || event.key === 'k')) ||
        event.key === '/'
      ) {
        event.preventDefault(); // Prevent default browser search behavior
        onFocusSearch();
      }

      // Check for Escape to unfocus search
      if (event.key === 'Escape') {
        onUnfocusSearch();
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [onUndo, onFocusSearch, onUnfocusSearch]);
} 