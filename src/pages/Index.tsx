
import React, { useState } from "react";
import { useImageStore, ImageItem } from "@/hooks/useImageStore";
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
  const { 
    images, 
    isUploading, 
    isLoading, 
    isElectronAvailable,
    addImage, 
    addVideo,
    addUrlCard, 
    removeImage 
  } = useImageStore();
  const [searchQuery, setSearchQuery] = useState("");
  const [settingsOpen, setSettingsOpen] = useState(false);

  // Load saved API key on startup
  React.useEffect(() => {
    if (isElectronAvailable) {
      const savedApiKey = localStorage.getItem("openai-api-key");
      if (savedApiKey) {
        setOpenAIApiKey(savedApiKey);
      }
    }
  }, [isElectronAvailable]);

  // Show a warning if not running in Electron
  React.useEffect(() => {
    if (!isElectronAvailable) {
      toast.error("This app can only run in electron mode");
    }
  }, [isElectronAvailable]);

  const filteredImages = images.filter(image => {
    const query = searchQuery.toLowerCase();
    if (query === "") return true;
    
    if (image.type === "url") {
      return (
        (image.url?.toLowerCase().includes(query)) ||
        (image.title?.toLowerCase().includes(query))
      );
    }
    
    if (image.patterns && image.patterns.length > 0) {
      return image.patterns.some(pattern => pattern.name.toLowerCase().includes(query));
    }
    
    return false;
  });

  const handleImageClick = (image: ImageItem) => {
    // This function is just a placeholder now since the actual handling
    // is done inside the ImageGrid component with the new modal approach
    console.log("Image clicked:", image.id);
  };

  const handleDeleteImage = (id: string) => {
    removeImage(id);
  };

  if (!isElectronAvailable) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background p-4">
        <Toaster />
        <div className="bg-card p-8 rounded-lg shadow-lg max-w-md w-full text-center">
          <div className="w-20 h-20 bg-destructive/20 rounded-full flex items-center justify-center mx-auto mb-6">
            <span className="text-destructive text-2xl">⚠️</span>
          </div>
          <h1 className="text-2xl font-bold mb-4">Electron Mode Required</h1>
          <p className="text-muted-foreground mb-6">
            This application requires Electron to run properly as it needs access to the local file system.
            Please download and install the desktop version.
          </p>
          <Button
            className="w-full"
            onClick={() => window.location.href = "https://github.com/your-org/your-app-repo/releases"}
          >
            Download Desktop Version
          </Button>
        </div>
      </div>
    );
  }

  return (
    <UploadZone 
      onImageUpload={addImage}
      onVideoUpload={addVideo}
      onUrlAdd={addUrlCard} 
      isUploading={isUploading}
      isElectronAvailable={isElectronAvailable}
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
                  <input
                    type="file"
                    id="file-upload"
                    className="hidden"
                    accept="image/*,video/*"
                    multiple
                  />
                  <p className="text-lg mb-4">No items yet</p>
                  <label
                    htmlFor="file-upload"
                    className="bg-primary text-primary-foreground px-4 py-2 rounded cursor-pointer hover:bg-primary/90 transition-colors"
                  >
                    Upload media
                  </label>
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
      </div>
    </UploadZone>
  );
};

export default Index;
