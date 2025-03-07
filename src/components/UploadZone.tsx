
import React, { useCallback, useState, useEffect } from "react";
import { useToast } from "@/components/ui/use-toast";
import { validateImageFile, validateVideoFile, validateMediaFile } from "@/lib/imageUtils";
import { ImagePlus, FileVideo } from "lucide-react";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";

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
  const { toast } = useToast();
  const [isDragging, setIsDragging] = useState(false);
  const [isDraggingVideo, setIsDraggingVideo] = useState(false);

  const handleDragOver = useCallback((e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
    
    // Check if any of the dragged files is a video
    if (e.dataTransfer.items && e.dataTransfer.items.length > 0) {
      for (let i = 0; i < e.dataTransfer.items.length; i++) {
        if (e.dataTransfer.items[i].type.startsWith('video/')) {
          setIsDraggingVideo(true);
          break;
        }
      }
    }
    
    setIsDragging(true);
  }, []);

  const handleDragLeave = useCallback((e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragging(false);
    setIsDraggingVideo(false);
  }, []);

  const handleDrop = useCallback((e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragging(false);
    setIsDraggingVideo(false);

    if (isUploading) return;

    const files = Array.from(e.dataTransfer.files);
    
    // Process the dropped files
    files.forEach((file) => {
      if (validateImageFile(file) || validateVideoFile(file)) {
        onImageUpload(file);
      } else {
        toast({
          title: "Invalid file",
          description: "Please upload images (max 10MB) or videos (max 100MB).",
          variant: "destructive",
        });
      }
    });
  }, [isUploading, onImageUpload, toast]);

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
  }, [onUrlAdd, toast]);

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
              {isDraggingVideo ? (
                <FileVideo className="w-12 h-12 text-primary mb-4" />
              ) : (
                <ImagePlus className="w-12 h-12 text-primary mb-4" />
              )}
              <p className="text-xl font-medium">
                {isDraggingVideo ? "Drop video to add" : "Drop images to add"}
              </p>
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
        />
      </div>
    </>
  );
};

export default UploadZone;
