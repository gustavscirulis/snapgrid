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
import SettingsPanel from "@/components/SettingsPanel";
import WindowControls from "@/components/WindowControls";

const Index = () => {
  const { images, isUploading, isLoading, addImage, removeImage, undoDelete, canUndo } = useImageStore();
  const [searchQuery, setSearchQuery] = useState("");
  const [isElectron, setIsElectron] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const searchInputRef = useRef<HTMLInputElement>(null);

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
    }
  });

  useEffect(() => {
    const isRunningInElectron = window && 
      typeof window.electron !== 'undefined' && 
      window.electron !== null;
      
    console.log("Electron detection:", {
      electronExists: typeof window.electron !== 'undefined',
      electronValue: window.electron
    });
    
    setIsElectron(isRunningInElectron);
    
    if (isRunningInElectron) {
      console.log("Running in Electron mode");
    } else {
      console.log("Running in browser mode. Electron APIs not available.");
      toast.warning("Running in browser mode. Local storage features are not available.");
    }
    
    const savedApiKey = localStorage.getItem("openai-api-key");
    if (savedApiKey) {
      setOpenAIApiKey(savedApiKey);
    }
  }, []);

  const filteredImages = images.filter(image => {
    const query = searchQuery.toLowerCase();
    if (query === "") return true;
    
    if (image.patterns && image.patterns.length > 0) {
      return image.patterns.some(pattern => pattern.name.toLowerCase().includes(query));
    }
    
    return false;
  });

  const handleImageClick = (image: ImageItem) => {
    console.log("Image clicked:", image.id);
  };

  const handleDeleteImage = (id: string) => {
    removeImage(id);
  };

  return (
    <UploadZone 
      onImageUpload={addImage} 
      isUploading={isUploading}
    >
      <div className="min-h-screen flex flex-col">
        <Toaster />
        <header className="sticky top-0 z-10 bg-background/80 backdrop-blur-md border-b border-border py-4 px-6 relative">
          <div className="absolute inset-0 draggable"></div>
          <div className="relative mx-auto flex items-center">
            <div className="w-8 draggable"></div> {/* Left draggable area */}
            <div className="flex-1 flex justify-center">
              <div className="relative w-96 non-draggable">
                <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                <Input
                  ref={searchInputRef}
                  placeholder="Search..."
                  className="pl-9 bg-white dark:bg-neutral-900"
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
                className="h-8 w-8 non-draggable"
              >
                <Settings className="h-5 w-5" />
                <span className="sr-only">Settings</span>
              </Button>
            </div>
          </div>
          <WindowControls />
        </header>

        <main className="mx-auto flex-1 flex flex-col min-h-0">
          {isLoading ? (
            <div className="flex justify-center items-center h-64">
              <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary"></div>
            </div>
          ) : (
            <>
              <ImageGrid 
                images={filteredImages} 
                onImageClick={handleImageClick} 
                onImageDelete={handleDeleteImage}
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
