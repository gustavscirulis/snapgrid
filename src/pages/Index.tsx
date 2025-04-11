import React, { useState, useEffect, useRef } from "react";
import { useImageStore, ImageItem } from "@/hooks/useImageStore";
import { useKeyboardShortcuts } from "@/hooks/useKeyboardShortcuts";
import UploadZone from "@/components/UploadZone";
import ImageGrid from "@/components/ImageGrid";
import { Search, Settings } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { setOpenAIApiKey } from "@/services/aiAnalysisService";
import { Toaster, toast } from "sonner";
import { SettingsPanel } from "@/components/SettingsPanel";
import WindowControls from "@/components/WindowControls";

// Helper function to convert File URL to File object
const urlToFile = async (url: string, filename: string): Promise<File> => {
  const response = await fetch(url);
  const blob = await response.blob();
  return new File([blob], filename, { type: blob.type });
};

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
    retryAnalysis
  } = useImageStore();
  const [searchQuery, setSearchQuery] = useState("");
  const [isElectron, setIsElectron] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [simulateEmptyState, setSimulateEmptyState] = useState(false);
  const searchInputRef = useRef<HTMLInputElement>(null);

  // Load developer settings on mount
  useEffect(() => {
    // Check if we should simulate empty state (only in dev mode)
    const savedSetting = localStorage.getItem('dev_simulate_empty_state');
    setSimulateEmptyState(savedSetting === 'true');
  }, []);

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
              await addImage(file);
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
  }, [addImage]);

  useEffect(() => {
    const isRunningInElectron = window && 
      typeof window.electron !== 'undefined' && 
      window.electron !== null;
      
    setIsElectron(isRunningInElectron);
    
    if (isRunningInElectron) {
      // Set up listeners for menu-triggered events
      const cleanupImportFiles = window.electron.onImportFiles(async (filePaths) => {
        try {
          // Remove the toast that shows importing status
          
          for (const filePath of filePaths) {
            try {
              // Use direct file import method
              await importFromFilePath(filePath);
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
    } else {
      toast.warning("Running in browser mode. Local storage features are not available.");
    }
    
    // Initial loading of API key happens in the aiAnalysisService
    // No need to manually load from localStorage here as it's handled by the service
  }, [addImage, importFromFilePath]);

  const filteredImages = images.filter(image => {
    const query = searchQuery.toLowerCase();
    if (query === "") return true;
    
    // If query starts with "vid", show all videos
    if (query.startsWith("vid")) {
      return image.type === "video";
    }
    
    // If query starts with "img", show all images
    if (query.startsWith("img")) {
      return image.type === "image";
    }
    
    // Otherwise, search in patterns and imageContext
    if (image.patterns && image.patterns.length > 0) {
      // Search in pattern names
      const patternMatch = image.patterns.some(pattern => 
        pattern.name.toLowerCase().includes(query)
      );
      
      // Also search in imageContext if it exists at the image level
      const contextMatch = image.imageContext ? 
        image.imageContext.toLowerCase().includes(query) : false;
      
      return patternMatch || contextMatch;
    }
    
    return false;
  }).sort((a, b) => {
    // Only sort by confidence when there's a search query and it's not a media type filter
    const query = searchQuery.toLowerCase();
    if (query === "" || query.startsWith("vid") || query.startsWith("img")) {
      return 0; // Keep original order
    }
    
    // Find the highest confidence score for matching patterns in each image
    const aMaxConfidence = a.patterns?.reduce((max, pattern) => {
      // Match in pattern name
      const matchesPattern = pattern.name.toLowerCase().includes(query);
      
      if (matchesPattern) {
        return Math.max(max, pattern.confidence);
      }
      return max;
    }, 0) || 0;
    
    const bMaxConfidence = b.patterns?.reduce((max, pattern) => {
      // Match in pattern name
      const matchesPattern = pattern.name.toLowerCase().includes(query);
      
      if (matchesPattern) {
        return Math.max(max, pattern.confidence);
      }
      return max;
    }, 0) || 0;
    
    // If searching for context that matches, prioritize those images
    if (query && a.imageContext && a.imageContext.toLowerCase().includes(query)) {
      return -1; // a comes first
    }
    if (query && b.imageContext && b.imageContext.toLowerCase().includes(query)) {
      return 1; // b comes first
    }
    
    // Sort by confidence score (highest first)
    return bMaxConfidence - aMaxConfidence;
  });

  const handleImageClick = (image: ImageItem) => {
  };

  const handleDeleteImage = (id: string) => {
    removeImage(id);
  };

  // Determine if we're in empty state - consider both actual emptiness and simulated empty state
  const isEmpty = images.length === 0 || simulateEmptyState;

  return (
    <UploadZone 
      onImageUpload={addImage} 
      isUploading={isUploading}
    >
      <div className={`min-h-screen flex flex-col ${isEmpty ? 'overflow-hidden' : ''}`}>
        <Toaster />
        <header className="sticky top-0 z-10 bg-gray-100/90 dark:bg-zinc-900/90 backdrop-blur-lg py-4 px-6 relative">
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

        <main className={`mx-auto flex-1 flex flex-col min-h-0 w-full ${isEmpty ? 'overflow-hidden' : ''}`}>
          {isLoading ? (
            <div className="flex justify-center items-center h-screen">
              <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary"></div>
            </div>
          ) : (
            <>
              <ImageGrid 
                images={simulateEmptyState ? [] : filteredImages} 
                onImageClick={handleImageClick} 
                onImageDelete={handleDeleteImage}
                searchQuery={searchQuery}
                onOpenSettings={() => setSettingsOpen(true)}
                settingsOpen={settingsOpen}
                retryAnalysis={retryAnalysis}
              />
            </>
          )}
        </main>

        <SettingsPanel
          open={settingsOpen}
          onOpenChange={setSettingsOpen}
        />
      </div>
    </UploadZone>
  );
};

export default Index;
