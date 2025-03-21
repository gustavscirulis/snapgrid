import { useEffect } from 'react';

interface KeyboardShortcutsProps {
  onUndo: () => void;
}

export function useKeyboardShortcuts({ onUndo }: KeyboardShortcutsProps) {
  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      // Check for Command+Z (Mac) or Ctrl+Z (Windows/Linux)
      if ((event.metaKey || event.ctrlKey) && event.key === 'z') {
        event.preventDefault(); // Prevent default browser undo behavior
        onUndo();
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [onUndo]);
} 