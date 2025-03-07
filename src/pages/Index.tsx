
import React, { useState, useEffect } from "react";
import { useImageStore, ImageItem } from "@/hooks/useImageStore";
import UploadZone from "@/components/UploadZone";
import ImageGrid from "@/components/ImageGrid";
import ImageModal from "@/components/ImageModal";
import { Search, Settings } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { setOpenAIApiKey } from "@/services/aiAnalysisService";
import { Toaster, toast } from "sonner";
import SettingsPanel from "@/components/SettingsPanel";

// Add CSP meta tag to document head with expanded permissions for file:// protocol
const addCSPMetaTag = () => {
  if (typeof document !== 'undefined') {
    const meta = document.createElement('meta');
    meta.httpEquiv = 'Content-Security-Policy';
    meta.content = "default-src 'self' file:; img-src 'self' data: blob: https: file:; media-src 'self' data: blob: https: file:; script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self' https://api.openai.com;";
    document.head.appendChild(meta);
  }
};

const Index = () => {
  const { images, isUploading, isLoading, addImage, addUrlCard, removeImage, updateImageItem } = useImageStore();
  const [selectedImage, setSelectedImage] = useState<ImageItem | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [searchQuery, setSearchQuery] = useState("");
  const [isElectron, setIsElectron] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);

  useEffect(() => {
    // Add CSP meta tag on component mount - with expanded permissions for file:// protocol
    addCSPMetaTag();
    
    // Check if running in Electron - more reliable detection
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
      
      // Request filesystem access path from Electron - using the correct function name
      window.electron.getAppStorageDir().then((path) => {
        console.log("Storage path:", path);
      }).catch(err => {
        console.error("Failed to get storage path:", err);
      });
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
    }
    
    if (image.type === "video" && image.title) {
      return image.title.toLowerCase().includes(query);
    }
    
    if (image.patterns && image.patterns.length > 0) {
      return image.patterns.some(pattern => pattern.name.toLowerCase().includes(query));
    }
    
    return false;
  });

  const handleImageClick = (image: ImageItem) => {
    if (image.type === "url" && image.sourceUrl) {
      window.open(image.sourceUrl, "_blank", "noopener,noreferrer");
    } else {
      setSelectedImage(image);
      setModalOpen(true);
    }
  };

  const closeModal = () => {
    setModalOpen(false);
    setTimeout(() => setSelectedImage(null), 300);
  };

  const handleDeleteImage = (id: string) => {
    removeImage(id);
  };

  const handleImageUpdate = (updatedImage: ImageItem) => {
    updateImageItem(updatedImage);
  };

  return (
    <UploadZone 
      onImageUpload={addImage} 
      onUrlAdd={addUrlCard} 
      isUploading={isUploading}
    >
      <div className="min-h-screen">
        <Toaster />
        <header className="sticky top-0 z-10 bg-background/80 backdrop-blur-md border-b border-border py-4 px-6">
          <div className="max-w-screen-xl mx-auto flex justify-between items-center">
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
            <ImageGrid 
              images={filteredImages} 
              onImageClick={handleImageClick} 
              onImageDelete={handleDeleteImage}
            />
          )}
        </main>

        <ImageModal
          isOpen={modalOpen}
          onClose={closeModal}
          image={selectedImage}
          onImageUpdate={handleImageUpdate}
        />

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
