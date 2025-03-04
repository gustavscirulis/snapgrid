
import React, { useState, useEffect } from "react";
import { useImageStore, ImageItem } from "@/hooks/useImageStore";
import UploadZone from "@/components/UploadZone";
import ImageGrid from "@/components/ImageGrid";
import ImageModal from "@/components/ImageModal";
import { ImagePlus, Link, Search, Folder, HardDrive } from "lucide-react";
import { Button } from "@/components/ui/button";
import { ApiKeyInput } from "@/components/ApiKeyInput";
import { setOpenAIApiKey } from "@/services/aiAnalysisService";
import { Input } from "@/components/ui/input";
import { Toaster, toast } from "sonner";

const Index = () => {
  const { images, isUploading, isLoading, addImage, addUrlCard, removeImage } = useImageStore();
  const [selectedImage, setSelectedImage] = useState<ImageItem | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [urlModalOpen, setUrlModalOpen] = useState(false);
  const [searchQuery, setSearchQuery] = useState("");
  const [isElectron, setIsElectron] = useState(false);
  const [storageDir, setStorageDir] = useState<string | null>(null);

  useEffect(() => {
    // Check if running in Electron
    const electronAvailable = window.electron !== undefined;
    setIsElectron(electronAvailable);
    
    // Get storage directory if in Electron
    if (electronAvailable) {
      window.electron.getAppStorageDir().then((dir: string) => {
        setStorageDir(dir);
      });
    }
    
    // Load API key from localStorage
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

  const openStorageLocation = () => {
    if (window.electron) {
      window.electron.openStorageDir()
        .then(() => {
          toast.success("Storage folder opened");
        })
        .catch((error: any) => {
          toast.error("Failed to open storage folder: " + error);
        });
    }
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
            <h1 className="text-xl font-medium">
              UI Reference
              {isElectron && <span className="ml-2 text-xs bg-green-100 text-green-800 rounded-full px-2 py-1">Desktop</span>}
            </h1>
            <div className="flex gap-2">
              <div className="relative w-64">
                <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                <Input
                  placeholder="Search by pattern or URL..."
                  className="pl-9"
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                />
              </div>
              <ApiKeyInput />
              {isElectron && (
                <Button
                  variant="outline"
                  size="sm"
                  className="flex items-center gap-1"
                  onClick={openStorageLocation}
                >
                  <HardDrive className="h-4 w-4" />
                  <span>Storage</span>
                </Button>
              )}
              <Button
                variant="outline"
                size="sm"
                className="flex items-center gap-1"
                onClick={() => setUrlModalOpen(true)}
              >
                <Link className="h-4 w-4" />
                <span>Add URL</span>
              </Button>
              <label
                htmlFor="file-upload"
                className="inline-flex items-center gap-1 px-3 py-2 rounded-lg bg-primary text-primary-foreground hover:bg-primary/90 transition-colors cursor-pointer text-sm"
              >
                <ImagePlus className="h-4 w-4" />
                <span>Upload</span>
              </label>
            </div>
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
        />

        <footer className="py-6 text-center text-sm text-muted-foreground">
          <p>
            {isElectron 
              ? `Images are stored at: ${storageDir || "Loading..."} (Click 'Storage' button to open)` 
              : "Drag and drop images or paste URLs anywhere to add"}
          </p>
        </footer>
      </div>
    </UploadZone>
  );
};

export default Index;
