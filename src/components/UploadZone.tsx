import React, { useCallback, useState, useEffect, createContext, useContext } from "react";
import { useToast } from "@/components/ui/use-toast";
import { validateMediaFile } from "@/lib/imageUtils";
import { ImagePlus } from "lucide-react";

// Create a context for the drag state
export const DragContext = createContext<{ isDragging: boolean }>({ isDragging: false });

// Hook to use the drag context
export const useDragContext = () => useContext(DragContext);

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
  const dragCounter = React.useRef(0);

  const handleDragEnter = useCallback((e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
    dragCounter.current += 1;
    setIsDragging(true);
  }, []);

  const handleDragOver = useCallback((e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
    // Don't reset isDragging here
  }, []);

  const handleDragLeave = useCallback((e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
    dragCounter.current -= 1;
    
    if (dragCounter.current === 0) {
      setIsDragging(false);
    }
  }, []);

  const handleDrop = useCallback((e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
    dragCounter.current = 0;
    setIsDragging(false);

    if (isUploading) {
      return;
    }

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

  // Reset drag counter on unmount
  useEffect(() => {
    return () => {
      dragCounter.current = 0;
    };
  }, []);

  return (
    <DragContext.Provider value={{ isDragging }}>
      <div
        className={`min-h-screen w-full transition-all duration-300 ${
          isDragging ? "bg-primary/5 border-primary/30" : ""
        }`}
        onDragEnter={handleDragEnter}
        onDragOver={handleDragOver}
        onDragLeave={handleDragLeave}
        onDrop={handleDrop}
      >
        {children}
        
        {isDragging && (
          <div className="fixed inset-0 bg-background/40 backdrop-blur-sm flex items-center justify-center z-[150] pointer-events-none">
            <div className="bg-white dark:bg-zinc-900 p-8 rounded-2xl shadow-2xl flex flex-col items-center animate-bounce-slow">
              <ImagePlus className="w-16 h-16 text-gray-800 dark:text-gray-200 mb-4" />
              <p className="text-xl font-medium text-gray-900 dark:text-gray-100">Drop your file here</p>
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
    </DragContext.Provider>
  );
};

export default UploadZone;
