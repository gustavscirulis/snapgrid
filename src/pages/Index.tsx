
import React, { useState } from "react";
import { useImageStore, ImageItem } from "@/hooks/useImageStore";
import UploadZone from "@/components/UploadZone";
import ImageGrid from "@/components/ImageGrid";
import ImageModal from "@/components/ImageModal";
import { ImagePlus, Link } from "lucide-react";
import { Button } from "@/components/ui/button";

const Index = () => {
  const { images, isUploading, addImage, addUrlCard } = useImageStore();
  const [selectedImage, setSelectedImage] = useState<ImageItem | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [urlModalOpen, setUrlModalOpen] = useState(false);

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
    setTimeout(() => setSelectedImage(null), 300); // Clean up after animation completes
  };

  return (
    <UploadZone 
      onImageUpload={addImage} 
      onUrlAdd={addUrlCard} 
      isUploading={isUploading}
    >
      <div className="min-h-screen">
        <header className="sticky top-0 z-10 bg-background/80 backdrop-blur-md border-b border-border py-4 px-6">
          <div className="max-w-screen-xl mx-auto flex justify-between items-center">
            <h1 className="text-xl font-medium">UI Reference</h1>
            <div className="flex gap-2">
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
          <ImageGrid images={images} onImageClick={handleImageClick} />
        </main>

        <ImageModal
          isOpen={modalOpen}
          onClose={closeModal}
          image={selectedImage}
        />

        <footer className="py-6 text-center text-sm text-muted-foreground">
          <p>Drag and drop images or paste URLs anywhere to add</p>
        </footer>
      </div>
    </UploadZone>
  );
};

export default Index;
