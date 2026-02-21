import React, { useState, useEffect, useRef, useCallback } from "react";
import { useImageStore, ImageItem } from "@/hooks/useImageStore";
import { useSpaces, resolvePromptForSpace } from "@/hooks/useSpaces";
import { useKeyboardShortcuts } from "@/hooks/useKeyboardShortcuts";
import UploadZone from "@/components/UploadZone";
import ImageGrid from "@/components/ImageGrid";
import { SpaceTabBar } from "@/components/SpaceTabBar";
import { Search, Settings } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Toaster, toast } from "sonner";
import { SettingsPanel } from "@/components/SettingsPanel";
import WindowControls from "@/components/WindowControls";
import { motion } from "framer-motion";


const Index = () => {
  const {
    images,
    isUploading,
    isLoading,
    addImage,
    removeImage,
    undoDelete,
    canUndo,
    importFromFilePath,
    retryAnalysis,
    assignImageToSpace
  } = useImageStore();

  const {
    spaces,
    activeSpaceId,
    setActiveSpaceId,
    createSpace,
    renameSpace,
    deleteSpace,
    updateSpacePrompt,
    allSpacePromptConfig,
    updateAllSpacePrompt,
  } = useSpaces();

  const [searchQuery, setSearchQuery] = useState("");
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [simulateEmptyState, setSimulateEmptyState] = useState(false);
  const [thumbnailSize, setThumbnailSize] = useState<'small' | 'medium' | 'large' | 'xl'>('medium');
  const searchInputRef = useRef<HTMLInputElement>(null);

  // Refs to track values for callbacks that shouldn't re-register on space/prompt change
  const activeSpaceIdRef = useRef(activeSpaceId);
  activeSpaceIdRef.current = activeSpaceId;
  const spacesRef = useRef(spaces);
  spacesRef.current = spaces;
  const allSpacePromptConfigRef = useRef(allSpacePromptConfig);
  allSpacePromptConfigRef.current = allSpacePromptConfig;

  // Wrap addImage to auto-assign to active space with prompt resolution
  const addImageToActiveSpace = useCallback(async (file: File) => {
    const spaceId = activeSpaceIdRef.current ?? undefined;
    const prompt = resolvePromptForSpace(activeSpaceIdRef.current, spacesRef.current, allSpacePromptConfigRef.current);
    await addImage(file, spaceId, prompt);
  }, [addImage]);

  const importToActiveSpace = useCallback(async (filePath: string) => {
    const spaceId = activeSpaceIdRef.current ?? undefined;
    const prompt = resolvePromptForSpace(activeSpaceIdRef.current, spacesRef.current, allSpacePromptConfigRef.current);
    await importFromFilePath(filePath, spaceId, prompt);
  }, [importFromFilePath]);

  // Load saved preferences on mount
  useEffect(() => {
    // Check if we should simulate empty state (only in dev mode)
    const savedSetting = localStorage.getItem('dev_simulate_empty_state');
    setSimulateEmptyState(savedSetting === 'true');

    // Load saved thumbnail size from Electron preferences
    if (window.electron?.getUserPreference) {
      window.electron.getUserPreference('thumbnailSize', 'medium').then((result) => {
        if (result.success && result.value) {
          const size = result.value;
          if (size === 'small' || size === 'medium' || size === 'large' || size === 'xl') {
            setThumbnailSize(size);
          }
        }
      }).catch(console.error);
    }
  }, []);

  // Save thumbnail size changes to Electron preferences
  useEffect(() => {
    if (window.electron?.setUserPreference) {
      window.electron.setUserPreference('thumbnailSize', thumbnailSize).catch(console.error);
    }
  }, [thumbnailSize]);

  // Set up keyboard shortcuts
  useKeyboardShortcuts({
    onUndo: () => {
      if (canUndo) {
        undoDelete();
      }
    },
    onFocusSearch: () => {
      searchInputRef.current?.focus();
    },
    onUnfocusSearch: () => {
      searchInputRef.current?.blur();
    },
    onOpenSettings: () => {
      setSettingsOpen(true);
    },
    onZoomIn: () => {
      setThumbnailSize(current => {
        if (current === 'small') return 'medium';
        if (current === 'medium') return 'large';
        if (current === 'large') return 'xl';
        return 'xl'; // Already at largest
      });
    },
    onZoomOut: () => {
      setThumbnailSize(current => {
        if (current === 'xl') return 'large';
        if (current === 'large') return 'medium';
        if (current === 'medium') return 'small';
        return 'small'; // Already at smallest
      });
    }
  });

  // Prevent scrolling when in empty state
  useEffect(() => {
    // Consider empty if there are no images OR we're simulating empty state
    const hasImages = images.length > 0 && !simulateEmptyState;
    document.body.style.overflow = hasImages ? 'auto' : 'hidden';

    return () => {
      // Reset overflow when component unmounts
      document.body.style.overflow = 'auto';
    };
  }, [images.length, simulateEmptyState]);

  // Handle clipboard paste events
  useEffect(() => {
    const handlePaste = async (event: ClipboardEvent) => {
      const items = event.clipboardData?.items;
      if (!items) return;

      for (const item of items) {
        if (item.type.startsWith('image/')) {
          event.preventDefault();
          const file = item.getAsFile();
          if (file) {
            try {
              await addImageToActiveSpace(file);
            } catch (error) {
              console.error("Error pasting image:", error);
              toast.error("Failed to paste image");
            }
          }
          break;
        }
      }
    };

    window.addEventListener('paste', handlePaste);
    return () => window.removeEventListener('paste', handlePaste);
  }, [addImageToActiveSpace]);

  useEffect(() => {
    // Set up listeners for menu-triggered events
    const cleanupImportFiles = window.electron.onImportFiles(async (filePaths) => {
      try {
        for (const filePath of filePaths) {
          try {
            await importToActiveSpace(filePath);
          } catch (error) {
            console.error(`Error importing file ${filePath}:`, error);
            toast.error(`Failed to import file: ${filePath.split(/[\\/]/).pop()}`);
          }
        }
      } catch (error) {
        console.error('Error processing import files:', error);
        toast.error('Failed to import files');
      }
    });

    const cleanupOpenStorageLocation = window.electron.onOpenStorageLocation(() => {
      // Storage location is opened by the main process
    });

    const cleanupOpenSettings = window.electron.onOpenSettings(() => {
      setSettingsOpen(true);
    });

    // Clean up listeners on component unmount
    return () => {
      cleanupImportFiles();
      cleanupOpenStorageLocation();
      cleanupOpenSettings();
    };
  }, [addImageToActiveSpace, importToActiveSpace]);

  // Search filter applicable to any set of images
  const filterBySearch = (baseImages: ImageItem[]): ImageItem[] => {
    if (simulateEmptyState) return [];
    return baseImages.filter(image => {
      const query = searchQuery.toLowerCase();
      if (query === "") return true;

      if (query.startsWith("vid")) return image.type === "video";
      if (query.startsWith("img")) return image.type === "image";

      if (image.patterns && image.patterns.length > 0) {
        const patternMatch = image.patterns.some(pattern =>
          pattern.name.toLowerCase().includes(query)
        );
        const contextMatch = image.imageContext ?
          image.imageContext.toLowerCase().includes(query) : false;
        return patternMatch || contextMatch;
      }
      return false;
    }).sort((a, b) => {
      const query = searchQuery.toLowerCase();
      if (query === "" || query.startsWith("vid") || query.startsWith("img")) return 0;

      const aMaxConfidence = a.patterns?.reduce((max, pattern) => {
        const matchesPattern = pattern.name.toLowerCase().includes(query);
        return matchesPattern ? Math.max(max, pattern.confidence) : max;
      }, 0) || 0;

      const bMaxConfidence = b.patterns?.reduce((max, pattern) => {
        const matchesPattern = pattern.name.toLowerCase().includes(query);
        return matchesPattern ? Math.max(max, pattern.confidence) : max;
      }, 0) || 0;

      if (query && a.imageContext && a.imageContext.toLowerCase().includes(query)) return -1;
      if (query && b.imageContext && b.imageContext.toLowerCase().includes(query)) return 1;

      return bMaxConfidence - aMaxConfidence;
    });
  };

  const handleImageClick = (image: ImageItem) => {
  };

  const handleDeleteImage = (id: string) => {
    removeImage(id);
  };

  const handleAssignImageToSpace = useCallback(async (imageId: string, spaceId: string | null) => {
    const prompt = resolvePromptForSpace(spaceId, spaces, allSpacePromptConfig);
    await assignImageToSpace(imageId, spaceId, prompt);
  }, [assignImageToSpace, spaces, allSpacePromptConfig]);

  const handleRemoveFromSpace = useCallback(async (id: string) => {
    const prompt = resolvePromptForSpace(null, spaces, allSpacePromptConfig);
    await assignImageToSpace(id, null, prompt);
  }, [assignImageToSpace, spaces, allSpacePromptConfig]);

  const handleRetryAnalysis = useCallback(async (imageId: string) => {
    const image = images.find(img => img.id === imageId);
    const prompt = resolvePromptForSpace(image?.spaceId ?? null, spaces, allSpacePromptConfig);
    await retryAnalysis(imageId, prompt);
  }, [images, spaces, allSpacePromptConfig, retryAnalysis]);

  // Determine if we're in empty state - consider both actual emptiness and simulated empty state
  const isEmpty = images.length === 0 || simulateEmptyState;

  // Carousel: all spaces are side-by-side, animate x to the active page
  const activeIndex = activeSpaceId === null
    ? 0
    : spaces.findIndex(s => s.id === activeSpaceId) + 1;

  return (
    <UploadZone
      onImageUpload={addImageToActiveSpace}
      isUploading={isUploading}
    >
      <div className={`h-screen relative ${isEmpty ? 'overflow-hidden' : ''}`}>
        <Toaster />
        {/* Header + Tab bar overlay — floats above carousel so content scrolls behind it */}
        <div className="absolute top-0 left-0 right-0 z-10 bg-gray-100/90 dark:bg-zinc-900/90 backdrop-blur-lg">
          <header className="py-4 px-6 relative">
            <div className="absolute inset-0 draggable"></div>
            <div className="relative mx-auto flex items-center">
              <div className="w-8 draggable"></div> {/* Left draggable area */}
              <div className="flex-1 flex justify-center">
                <div className="relative w-96 non-draggable">
                  <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-gray-500 dark:text-gray-400 pointer-events-none z-10" />
                  <Input
                    ref={searchInputRef}
                    placeholder="Search..."
                    type="search"
                    className="pl-9 bg-gray-50 dark:bg-zinc-800 focus:bg-white dark:focus:bg-zinc-700 focus:ring-0 focus:border-gray-300 dark:focus:border-zinc-600"
                    value={searchQuery}
                    onChange={(e) => setSearchQuery(e.target.value)}
                  />
                </div>
              </div>
              <div className="flex items-center">
                <Button
                  variant="ghost"
                  size="icon"
                  onClick={() => setSettingsOpen(true)}
                  className="h-8 w-8 text-gray-500 hover:text-gray-900 dark:text-gray-400 dark:hover:text-gray-100 hover:bg-gray-100 dark:hover:bg-zinc-800 non-draggable transition-colors"
                  aria-label="Settings"
                >
                  <Settings className="h-5 w-5" />
                  <span className="sr-only">Settings</span>
                </Button>
              </div>
            </div>
            <WindowControls />
          </header>

          <SpaceTabBar
            spaces={spaces}
            activeSpaceId={activeSpaceId}
            onSelectSpace={setActiveSpaceId}
            onCreateSpace={createSpace}
            onRenameSpace={renameSpace}
            onDeleteSpace={deleteSpace}
          />
        </div>

        <main className="h-full overflow-hidden w-full">
          {isLoading ? (
            <div className="flex justify-center items-center" style={{ height: 'calc(100vh - 4rem)' }}>
              <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary"></div>
            </div>
          ) : (
            <motion.div
              className="flex h-full"
              animate={{ x: `${-activeIndex * 100}%` }}
              transition={{ type: "spring", damping: 30, stiffness: 300 }}
            >
              {/* "All" page */}
              <div className="w-full flex-shrink-0 overflow-y-auto h-full relative flex flex-col bg-gray-100 dark:bg-zinc-900 pt-[117px]">
                <ImageGrid
                  images={filterBySearch(images)}
                  onImageClick={handleImageClick}
                  onImageDelete={handleDeleteImage}
                  searchQuery={searchQuery}
                  onOpenSettings={() => setSettingsOpen(true)}
                  settingsOpen={settingsOpen}
                  retryAnalysis={handleRetryAnalysis}
                  thumbnailSize={thumbnailSize}
                  spaces={spaces}
                  activeSpaceId={null}
                  onAssignToSpace={handleAssignImageToSpace}
                />
              </div>
              {/* Space pages */}
              {spaces.map(space => (
                <div key={space.id} className="w-full flex-shrink-0 overflow-y-auto h-full relative flex flex-col bg-gray-100 dark:bg-zinc-900 pt-[117px]">
                  <ImageGrid
                    images={filterBySearch(images.filter(img => img.spaceId === space.id))}
                    onImageClick={handleImageClick}
                    onImageDelete={handleDeleteImage}
                    searchQuery={searchQuery}
                    onOpenSettings={() => setSettingsOpen(true)}
                    settingsOpen={settingsOpen}
                    retryAnalysis={handleRetryAnalysis}
                    thumbnailSize={thumbnailSize}
                    spaces={spaces}
                    activeSpaceId={space.id}
                    onAssignToSpace={handleAssignImageToSpace}
                    onRemoveFromSpace={handleRemoveFromSpace}
                  />
                </div>
              ))}
            </motion.div>
          )}
        </main>

        <SettingsPanel
          open={settingsOpen}
          onOpenChange={setSettingsOpen}
          spaces={spaces}
          activeSpaceId={activeSpaceId}
          allSpacePromptConfig={allSpacePromptConfig}
          onCreateSpace={createSpace}
          onRenameSpace={renameSpace}
          onDeleteSpace={deleteSpace}
          onUpdateSpacePrompt={updateSpacePrompt}
          onUpdateAllSpacePrompt={updateAllSpacePrompt}
        />
      </div>
    </UploadZone>
  );
};

export default Index;
