
import React, { useCallback, useState, useEffect } from "react";
import { useToast } from "@/components/ui/use-toast";
import { validateImageFile, validateVideoFile } from "@/lib/imageUtils";
import { ImagePlus } from "lucide-react";

interface UploadZoneProps {
  onImageUpload: (file: File) => void;
  onVideoUpload?: (file: File) => void;
  onUrlAdd: (url: string) => void;
  isUploading: boolean;
  children: React.ReactNode;
  isElectronAvailable: boolean;
}

const UploadZone: React.FC<UploadZoneProps> = ({
  onImageUpload,
  onVideoUpload,
  onUrlAdd,
  isUploading,
  children,
  isElectronAvailable,
}) => {
  const { toast } = useToast();
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

    if (!isElectronAvailable) {
      return;
    }

    if (isUploading) return;

    const files = Array.from(e.dataTransfer.files);
    
    // Process the dropped files
    files.forEach((file) => {
      if (validateImageFile(file)) {
        onImageUpload(file);
      } else if (validateVideoFile(file) && onVideoUpload) {
        onVideoUpload(file);
      } else {
        toast({
          title: "Invalid file",
          description: "Please upload supported media files (images up to 10MB, videos up to 100MB).",
          variant: "destructive",
        });
      }
    });
  }, [isElectronAvailable, isUploading, onImageUpload, onVideoUpload, toast]);

  // Add paste event listener to capture pasted URLs
  useEffect(() => {
    const handlePaste = (e: ClipboardEvent) => {
      if (!isElectronAvailable) return;
      
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
  }, [isElectronAvailable, onUrlAdd, toast]);

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
              <ImagePlus className="w-12 h-12 text-primary mb-4" />
              <p className="text-xl font-medium">Drop media to add</p>
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
          disabled={!isElectronAvailable}
        />
      </div>
    </>
  );
};

export default UploadZone;
