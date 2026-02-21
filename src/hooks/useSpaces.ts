import { useState, useCallback, useEffect, useRef } from "react";
import { DEFAULT_SYSTEM_PROMPT } from "@/services/aiAnalysisService";

export interface Space {
  id: string;
  name: string;
  order: number;
  createdAt: string;
  customPrompt?: string;
  useCustomPrompt?: boolean;
}

export interface AllSpacePromptConfig {
  customPrompt?: string;
  useCustomPrompt?: boolean;
}

export interface UseSpacesReturn {
  spaces: Space[];
  activeSpaceId: string | null;
  setActiveSpaceId: (id: string | null) => void;
  slideDirection: number;
  createSpace: (name: string) => Promise<Space>;
  renameSpace: (id: string, name: string) => Promise<void>;
  deleteSpace: (id: string) => Promise<void>;
  updateSpacePrompt: (id: string, customPrompt: string | undefined, useCustomPrompt: boolean) => Promise<void>;
  allSpacePromptConfig: AllSpacePromptConfig;
  updateAllSpacePrompt: (customPrompt: string | undefined, useCustomPrompt: boolean) => Promise<void>;
  isLoading: boolean;
}

export function resolvePromptForSpace(
  spaceId: string | null | undefined,
  spaces: Space[],
  allSpacePromptConfig: AllSpacePromptConfig
): string | undefined {
  let spaceName: string | undefined;
  let customInstructions: string | undefined;

  if (spaceId === null || spaceId === undefined) {
    if (allSpacePromptConfig.useCustomPrompt && allSpacePromptConfig.customPrompt) {
      customInstructions = allSpacePromptConfig.customPrompt;
    }
  } else {
    const space = spaces.find(s => s.id === spaceId);
    if (space) {
      spaceName = space.name;
      if (space.useCustomPrompt && space.customPrompt) {
        customInstructions = space.customPrompt;
      }
    }
  }

  const additions: string[] = [];
  if (spaceName) {
    additions.push(`This image belongs to a collection called "${spaceName}". Use this as context to inform your analysis — pay attention to aspects relevant to this theme.`);
  }
  if (customInstructions) {
    additions.push(customInstructions);
  }

  if (additions.length > 0) {
    return `${DEFAULT_SYSTEM_PROMPT}\n\nAdditional instructions:\n${additions.join('\n')}`;
  }
  return undefined;
}

function generateId(): string {
  return `space_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
}

export function useSpaces(): UseSpacesReturn {
  const [spaces, setSpaces] = useState<Space[]>([]);
  const [activeSpaceId, setActiveSpaceIdRaw] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [slideDirection, setSlideDirection] = useState(0);
  const [allSpacePromptConfig, setAllSpacePromptConfig] = useState<AllSpacePromptConfig>({});

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

  // Load spaces and allSpacePromptConfig from preferences on mount
  useEffect(() => {
    const load = async () => {
      try {
        if (window.electron?.getUserPreference) {
          const [spacesResult, allPromptResult] = await Promise.all([
            window.electron.getUserPreference('spaces', []),
            window.electron.getUserPreference('allSpacePrompt', {}),
          ]);
          if (spacesResult.success && spacesResult.value) {
            const loaded = Array.isArray(spacesResult.value) ? spacesResult.value : [];
            setSpaces(loaded.sort((a: Space, b: Space) => a.order - b.order));
          }
          if (allPromptResult.success && allPromptResult.value) {
            setAllSpacePromptConfig(allPromptResult.value);
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

  const updateSpacePrompt = useCallback(async (
    id: string,
    customPrompt: string | undefined,
    useCustomPrompt: boolean
  ) => {
    const updated = spaces.map(s =>
      s.id === id ? { ...s, customPrompt, useCustomPrompt } : s
    );
    setSpaces(updated);
    await persistSpaces(updated);
  }, [spaces, persistSpaces]);

  const updateAllSpacePrompt = useCallback(async (
    customPrompt: string | undefined,
    useCustomPrompt: boolean
  ) => {
    const config = { customPrompt, useCustomPrompt };
    setAllSpacePromptConfig(config);
    if (window.electron?.setUserPreference) {
      await window.electron.setUserPreference('allSpacePrompt', config);
    }
  }, []);

  return {
    spaces,
    activeSpaceId,
    setActiveSpaceId,
    slideDirection,
    createSpace,
    renameSpace,
    deleteSpace,
    updateSpacePrompt,
    allSpacePromptConfig,
    updateAllSpacePrompt,
    isLoading,
  };
}
