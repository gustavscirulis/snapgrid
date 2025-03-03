
import React, { useState } from "react";
import { useImageStore, ImageItem } from "@/hooks/useImageStore";
import UploadZone from "@/components/UploadZone";
import ImageGrid from "@/components/ImageGrid";
import ImageModal from "@/components/ImageModal";
import { ImagePlus } from "lucide-react";

const Index = () => {
  const { images, isUploading, addImage } = useImageStore();
  const [selectedImage, setSelectedImage] = useState<ImageItem | null>(null);
  const [modalOpen, setModalOpen] = useState(false);

  const handleImageClick = (image: ImageItem) => {
    setSelectedImage(image);
    setModalOpen(true);
  };

  const closeModal = () => {
    setModalOpen(false);
    setTimeout(() => setSelectedImage(null), 300); // Clean up after animation completes
  };

  return (
    <UploadZone onImageUpload={addImage} isUploading={isUploading}>
      <div className="min-h-screen">
        <header className="sticky top-0 z-10 bg-background/80 backdrop-blur-md border-b border-border py-4 px-6">
          <div className="max-w-screen-xl mx-auto flex justify-between items-center">
            <h1 className="text-xl font-medium">UI Reference</h1>
            <label
              htmlFor="file-upload"
              className="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-primary text-primary-foreground hover:bg-primary/90 transition-colors cursor-pointer"
            >
              <ImagePlus className="h-4 w-4" />
              <span>Upload</span>
            </label>
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
          <p>Drag and drop images anywhere to upload</p>
        </footer>
      </div>
    </UploadZone>
  );
};

export default Index;
