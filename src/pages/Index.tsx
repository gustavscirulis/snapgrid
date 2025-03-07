
import React, { useState, useEffect } from "react";
import { useImageStore, ImageItem } from "@/hooks/useImageStore";
import UploadZone from "@/components/UploadZone";
import ImageGrid from "@/components/ImageGrid";
import { Search, Settings, FileVideo, ImagePlus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { setOpenAIApiKey } from "@/services/aiAnalysisService";
import { Toaster, toast } from "sonner";
import SettingsPanel from "@/components/SettingsPanel";
import WindowControls from "@/components/WindowControls";

const Index = () => {
  const { images, isUploading, isLoading, addImage, addUrlCard, removeImage } = useImageStore();
  const [searchQuery, setSearchQuery] = useState("");
  const [isElectron, setIsElectron] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);

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
    
    if (image.type === "url") {
      return (
        (image.url?.toLowerCase().includes(query)) ||
        (image.title?.toLowerCase().includes(query))
      );
    } else if (image.type === "video") {
      // For videos, search by filename or type
      return image.url?.toLowerCase().includes(query) || 
             "video".includes(query);
    }
    
    if (image.patterns && image.patterns.length > 0) {
      return image.patterns.some(pattern => pattern.name.toLowerCase().includes(query));
    }
    
    return false;
  });

  const handleFileUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files) {
      Array.from(e.target.files).forEach(file => {
        addImage(file);
      });
    }
  };

  const handleImageClick = (image: ImageItem) => {
    // This function is just a placeholder now since the actual handling
    // is done inside the ImageGrid component with the new modal approach
    console.log(`${image.type} clicked:`, image.id);
  };

  const handleDeleteImage = (id: string) => {
    removeImage(id);
  };

  return (
    <UploadZone 
      onImageUpload={addImage} 
      onUrlAdd={addUrlCard} 
      isUploading={isUploading}
    >
      <div className="min-h-screen">
        <Toaster />
        <header className="sticky top-0 z-10 bg-background/80 backdrop-blur-md border-b border-border py-4 px-6 relative draggable">
          <WindowControls />
          <div className="max-w-screen-xl mx-auto flex justify-between items-center non-draggable">
            <div className="w-8"></div> {/* Empty div for centering */}
            <div className="relative w-64">
              <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-muted-foreground" />
              <Input
                placeholder="Search by pattern or URL..."
                className="pl-9"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
              />
            </div>
            <Button
              variant="ghost"
              size="icon"
              onClick={() => setSettingsOpen(true)}
              className="h-8 w-8"
            >
              <Settings className="h-5 w-5" />
              <span className="sr-only">Settings</span>
            </Button>
          </div>
        </header>

        <main className="max-w-screen-xl mx-auto">
          {isLoading ? (
            <div className="flex justify-center items-center h-64">
              <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary"></div>
            </div>
          ) : (
            <>
              {images.length === 0 && (
                <div className="flex flex-col items-center justify-center h-64 text-muted-foreground">
                  <div className="flex space-x-4 mt-4">
                    <label
                      htmlFor="file-upload"
                      className="inline-flex items-center px-4 py-2 bg-primary text-white rounded-lg hover:bg-primary/90 transition-colors cursor-pointer"
                      onClick={() => {
                        const input = document.getElementById('file-upload') as HTMLInputElement;
                        if (input) {
                          input.click();
                        }
                      }}
                    >
                      <ImagePlus className="h-4 w-4 mr-2" />
                      Upload Media
                    </label>
                  </div>
                  <input
                    type="file"
                    id="file-upload"
                    className="hidden"
                    accept="image/*,video/*"
                    multiple
                    onChange={handleFileUpload}
                  />
                </div>
              )}
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

        <footer className="py-6 text-center text-sm text-muted-foreground">
          {!isElectron && (
            <p>
              Running in browser mode. Local storage features are not available.
            </p>
          )}
        </footer>
      </div>
    </UploadZone>
  );
};

export default Index;
