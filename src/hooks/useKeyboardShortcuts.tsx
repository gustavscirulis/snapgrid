import { useEffect } from 'react';

interface KeyboardShortcutsProps {
  onUndo: () => void;
  onFocusSearch: () => void;
  onUnfocusSearch: () => void;
  onOpenSettings?: () => void;
  onZoomIn?: () => void;
  onZoomOut?: () => void;
}

export function useKeyboardShortcuts({ 
  onUndo, 
  onFocusSearch, 
  onUnfocusSearch,
  onOpenSettings,
  onZoomIn,
  onZoomOut
}: KeyboardShortcutsProps) {
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

      // Check for Command+comma to open settings (Mac standard)
      if ((event.metaKey || event.ctrlKey) && event.key === ',') {
        event.preventDefault();
        onOpenSettings?.();
      }

      // Check for Escape to unfocus search
      if (event.key === 'Escape') {
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
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [onUndo, onFocusSearch, onUnfocusSearch, onOpenSettings, onZoomIn, onZoomOut]);
} 