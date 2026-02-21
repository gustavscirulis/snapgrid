import { useState, useCallback, useEffect, useRef } from "react";

export interface Space {
  id: string;
  name: string;
  order: number;
  createdAt: string;
}

export interface UseSpacesReturn {
  spaces: Space[];
  activeSpaceId: string | null;
  setActiveSpaceId: (id: string | null) => void;
  slideDirection: number;
  createSpace: (name: string) => Promise<Space>;
  renameSpace: (id: string, name: string) => Promise<void>;
  deleteSpace: (id: string) => Promise<void>;
  isLoading: boolean;
}

function generateId(): string {
  return `space_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
}

export function useSpaces(): UseSpacesReturn {
  const [spaces, setSpaces] = useState<Space[]>([]);
  const [activeSpaceId, setActiveSpaceIdRaw] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [slideDirection, setSlideDirection] = useState(0);

  const currentIndexRef = useRef(0);

  const setActiveSpaceId = useCallback((id: string | null) => {
    const newIndex = id === null ? 0 : (() => {
      const idx = spaces.findIndex(s => s.id === id);
      return idx === -1 ? 0 : idx + 1;
    })();
    setSlideDirection(newIndex - currentIndexRef.current);
    currentIndexRef.current = newIndex;
    setActiveSpaceIdRaw(id);
  }, [spaces]);

  // Load spaces from preferences on mount
  useEffect(() => {
    const load = async () => {
      try {
        if (window.electron?.getUserPreference) {
          const result = await window.electron.getUserPreference('spaces', []);
          if (result.success && result.value) {
            const loaded = Array.isArray(result.value) ? result.value : [];
            setSpaces(loaded.sort((a: Space, b: Space) => a.order - b.order));
          }
        }
      } catch (error) {
        console.error("Error loading spaces:", error);
      }
      setIsLoading(false);
    };
    load();
  }, []);

  const persistSpaces = useCallback(async (updated: Space[]) => {
    if (window.electron?.setUserPreference) {
      await window.electron.setUserPreference('spaces', updated);
    }
  }, []);

  const createSpace = useCallback(async (name: string): Promise<Space> => {
    const newSpace: Space = {
      id: generateId(),
      name,
      order: spaces.length,
      createdAt: new Date().toISOString(),
    };
    const updated = [...spaces, newSpace];
    setSpaces(updated);
    await persistSpaces(updated);
    return newSpace;
  }, [spaces, persistSpaces]);

  const renameSpace = useCallback(async (id: string, name: string) => {
    const updated = spaces.map(s => s.id === id ? { ...s, name } : s);
    setSpaces(updated);
    await persistSpaces(updated);
  }, [spaces, persistSpaces]);

  const deleteSpace = useCallback(async (id: string) => {
    const updated = spaces
      .filter(s => s.id !== id)
      .map((s, i) => ({ ...s, order: i }));
    setSpaces(updated);
    await persistSpaces(updated);
    // If we deleted the active space, go back to All
    if (activeSpaceId === id) {
      setActiveSpaceIdRaw(null);
      currentIndexRef.current = 0;
    }
  }, [spaces, activeSpaceId, persistSpaces]);

  return {
    spaces,
    activeSpaceId,
    setActiveSpaceId,
    slideDirection,
    createSpace,
    renameSpace,
    deleteSpace,
    isLoading,
  };
}
