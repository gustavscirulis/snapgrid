import React, { useCallback, useState, useEffect, createContext, useContext, useRef } from "react";
import { useToast } from "@/components/ui/use-toast";
import { validateMediaFile } from "@/lib/imageUtils";


// Create a context for the drag state
export const DragContext = createContext<{
  isDragging: boolean;
  setInternalDragActive: (active: boolean) => void;
  draggedImageId: string | null;
  setDraggedImageId: (id: string | null) => void;
}>({
  isDragging: false,
  setInternalDragActive: () => {},
  draggedImageId: null,
  setDraggedImageId: () => {},
});

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
  const [isInternalDragActive, setIsInternalDragActive] = useState(false);
  const [draggedImageId, setDraggedImageId] = useState<string | null>(null);
  const dragCounter = React.useRef(0);

  // Ref-based guard that survives the startDrag → dragend → OS drop race condition.
  // When startDrag takes over, dragend fires immediately (clearing state), but the
  // OS may deliver a file drop back into the app up to ~1s later. The ref stays true
  // during that window so handleDrop correctly ignores the re-imported file.
  const internalDragRef = useRef(false);
  const internalDragTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const handleSetInternalDragActive = useCallback((active: boolean) => {
    setIsInternalDragActive(active);
    if (active) {
      // Clear any pending timer
      if (internalDragTimerRef.current) {
        clearTimeout(internalDragTimerRef.current);
        internalDragTimerRef.current = null;
      }
      internalDragRef.current = true;
    } else {
      // Delay clearing the ref to survive the startDrag race condition.
      // startDrag fires dragend immediately, then the OS may deliver a file
      // drop back into the app seconds later. 10s covers long drag operations.
      internalDragTimerRef.current = setTimeout(() => {
        internalDragRef.current = false;
        internalDragTimerRef.current = null;
      }, 10000);
    }
  }, []);

  const handleDragEnter = useCallback((e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
    dragCounter.current += 1;

    // Only set isDragging if this is not an internal drag operation
    if (!internalDragRef.current) {
      setIsDragging(true);
    }
  }, []);

  const handleDragOver = useCallback((e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
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

    // If this is an internal drag operation (including delayed startDrag re-drops), skip
    if (internalDragRef.current) {
      return;
    }

    if (isUploading) {
      return;
    }

    const files = Array.from(e.dataTransfer.files);

    files.forEach((file) => {
      if (validateMediaFile(file)) {
        onImageUpload(file);
      } else {
        toast({
          title: "Invalid file",
          description: "Please upload images (jpg, png, gif, etc.) or videos (mp4, webm, ogg) only.",
          variant: "destructive",
        });
      }
    });
  }, [isUploading, onImageUpload, toast]);

  // After any drop lands in the window, clear the internal guard shortly after.
  // This lets the guard block the re-import in handleDrop, then resets for future use.
  useEffect(() => {
    const handleAnyDrop = () => {
      if (internalDragRef.current) {
        setTimeout(() => {
          internalDragRef.current = false;
          if (internalDragTimerRef.current) {
            clearTimeout(internalDragTimerRef.current);
            internalDragTimerRef.current = null;
          }
        }, 200);
      }
    };
    document.addEventListener('drop', handleAnyDrop);
    return () => document.removeEventListener('drop', handleAnyDrop);
  }, []);

  // Clean up on unmount
  useEffect(() => {
    return () => {
      dragCounter.current = 0;
      if (internalDragTimerRef.current) {
        clearTimeout(internalDragTimerRef.current);
      }
    };
  }, []);

  return (
    <DragContext.Provider value={{ isDragging, setInternalDragActive: handleSetInternalDragActive, draggedImageId, setDraggedImageId }}>
      <div
        className="min-h-screen w-full"
        onDragEnter={handleDragEnter}
        onDragOver={handleDragOver}
        onDragLeave={handleDragLeave}
        onDrop={handleDrop}
      >
        {children}

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
