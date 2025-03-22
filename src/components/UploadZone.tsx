import React, { useCallback, useState, useEffect } from "react";
import { useToast } from "@/components/ui/use-toast";
import { validateMediaFile } from "@/lib/imageUtils";
import { ImagePlus } from "lucide-react";

interface UploadZoneProps {
  onImageUpload: (file: File) => void;
  isUploading: boolean;
  children: React.ReactNode;
}

const UploadZone: React.FC<UploadZoneProps> = ({
  onImageUpload,
  isUploading,
  children,
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

    if (isUploading) return;

    const files = Array.from(e.dataTransfer.files);
    
    // Process the dropped files
    files.forEach((file) => {
      if (validateMediaFile(file)) {
        onImageUpload(file);
      } else {
        toast({
          title: "Invalid file",
          description: "Please upload images or videos only.",
          variant: "destructive",
        });
      }
    });
  }, [isUploading, onImageUpload, toast]);

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
            <div className="bg-card p-6 rounded-lg shadow-lg flex flex-col items-center animate-float">
              <ImagePlus className="w-12 h-12 text-primary" />
            </div>
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
