
import React, { useCallback, useState, useEffect } from "react";
import { toast } from "sonner";
import { validateMediaFile } from "@/lib/imageUtils";
import { ImagePlus, VideoIcon } from "lucide-react";

interface UploadZoneProps {
  onImageUpload: (file: File) => void;
  onUrlAdd: (url: string) => void;
  isUploading: boolean;
  children: React.ReactNode;
}

const UploadZone: React.FC<UploadZoneProps> = ({
  onImageUpload,
  onUrlAdd,
  isUploading,
  children,
}) => {
  const [isDragging, setIsDragging] = useState(false);

  const handleDragOver = useCallback((e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragging(true);
  }, []);

  const handleDragLeave = useCallback((e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragging(false);
  }, []);

  const handleDrop = useCallback((e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragging(false);

    if (isUploading) return;

    const files = Array.from(e.dataTransfer.files);
    
    // Process the dropped files
    files.forEach((file) => {
      console.log("Dropped file:", file.name, "Type:", file.type);
      const validation = validateMediaFile(file);
      if (validation.valid) {
        onImageUpload(file);
      } else {
        toast({
          title: "Invalid file",
          description: validation.message || "Please upload images (max 10MB) or videos (max 50MB)",
          variant: "destructive",
        });
      }
    });
  }, [isUploading, onImageUpload]);

  // Add paste event listener to capture pasted URLs
  useEffect(() => {
    const handlePaste = (e: ClipboardEvent) => {
      const pastedText = e.clipboardData?.getData('text');
      if (pastedText) {
        try {
          const url = new URL(pastedText);
          if (url.protocol === 'http:' || url.protocol === 'https:') {
            e.preventDefault();
            onUrlAdd(pastedText);
            toast({
              title: "URL added",
              description: "The URL card has been added to your collection.",
            });
          }
        } catch (error) {
          // Not a valid URL, ignore
        }
      }
    };

    document.addEventListener('paste', handlePaste);
    return () => {
      document.removeEventListener('paste', handlePaste);
    };
  }, [onUrlAdd]);

  const handleFileInputChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    if (isUploading) return;

    const files = Array.from(e.target.files || []);
    
    files.forEach((file) => {
      console.log("Selected file:", file.name, "Type:", file.type);
      const validation = validateMediaFile(file);
      if (validation.valid) {
        onImageUpload(file);
      } else {
        toast({
          title: "Invalid file",
          description: validation.message || "Please upload images (max 10MB) or videos (max 50MB)",
          variant: "destructive",
        });
      }
    });
    
    // Reset the input so the same file can be selected again
    e.target.value = '';
  }, [isUploading, onImageUpload]);

  return (
    <>
      <div
        className={`min-h-screen w-full transition-all duration-300 ${
          isDragging ? "bg-primary/5 border-primary/30" : ""
        }`}
        onDragOver={handleDragOver}
        onDragLeave={handleDragLeave}
        onDrop={handleDrop}
      >
        {children}
        
        {isDragging && (
          <div className="fixed inset-0 bg-background/80 backdrop-blur-sm flex items-center justify-center z-50 pointer-events-none">
            <div className="bg-card p-8 rounded-lg shadow-lg flex flex-col items-center animate-float">
              <div className="flex gap-2">
                <ImagePlus className="w-10 h-10 text-primary" />
                <VideoIcon className="w-10 h-10 text-primary" />
              </div>
              <p className="text-xl font-medium mt-4">Drop media to add</p>
              <p className="text-sm text-muted-foreground mt-2">Images or videos</p>
            </div>
          </div>
        )}
        
        {isUploading && (
          <div className="fixed bottom-6 right-6 bg-card p-4 rounded-lg shadow-lg z-40 animate-slide-up">
            <p className="text-sm font-medium flex items-center">
              <span className="inline-block w-4 h-4 border-2 border-primary border-t-transparent rounded-full animate-spin mr-2"></span>
              Adding to collection...
            </p>
          </div>
        )}
        
        <input
          type="file"
          id="file-upload"
          className="hidden"
          accept="image/*,video/*"
          multiple
          onChange={handleFileInputChange}
        />
      </div>
    </>
  );
};

export default UploadZone;
