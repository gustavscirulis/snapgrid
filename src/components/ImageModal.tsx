
import React, { useState, useEffect } from "react";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { ImageItem, PatternTag } from "@/hooks/useImageStore";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Separator } from "@/components/ui/separator";
import { Badge } from "@/components/ui/badge";
import { X } from "lucide-react";

interface ImageModalProps {
  isOpen: boolean;
  onClose: () => void;
  image: ImageItem | null;
  onImageUpdate?: (image: ImageItem) => void;
}

const ImageModal: React.FC<ImageModalProps> = ({
  isOpen,
  onClose,
  image,
  onImageUpdate,
}) => {
  const [title, setTitle] = useState("");
  const [patterns, setPatterns] = useState<PatternTag[]>([]);
  const [newPattern, setNewPattern] = useState("");

  // Reset state when image changes
  useEffect(() => {
    if (image) {
      setTitle(image.title || "");
      setPatterns(image.patterns || []);
    } else {
      setTitle("");
      setPatterns([]);
    }
  }, [image]);

  const handleSave = () => {
    if (image && onImageUpdate) {
      onImageUpdate({
        ...image,
        title,
        patterns,
      });
    }
    onClose();
  };

  const addPattern = () => {
    if (newPattern.trim() && !patterns.some(p => p.name.toLowerCase() === newPattern.toLowerCase())) {
      setPatterns([...patterns, { name: newPattern.trim(), confidence: 1 }]);
      setNewPattern("");
    }
  };

  const removePattern = (index: number) => {
    setPatterns(patterns.filter((_, i) => i !== index));
  };

  // Helper function to get correct source URL for files
  const getFileSrc = (filePath: string): string => {
    const isElectron = window && typeof window.electron !== 'undefined';
    
    if (isElectron) {
      // In development mode with Electron, we need to strip the file:// prefix
      // because the web security is disabled in dev mode
      return window.location.protocol === 'http:' 
        ? filePath 
        : `file://${filePath}`;
    }
    
    return filePath;
  };

  // If no image, return null 
  if (!image) return null;

  const isVideo = image.type === "video";
  const hasLocalFile = image.actualFilePath && image.actualFilePath.length > 0;
  
  const mediaSrc = hasLocalFile 
    ? getFileSrc(image.actualFilePath) 
    : image.url;
  
  return (
    <Dialog open={isOpen} onOpenChange={(open) => !open && onClose()}>
      <DialogContent className="max-w-4xl max-h-[90vh] overflow-auto">
        <DialogTitle className="flex justify-between items-center">
          <span className="text-xl font-semibold">
            {image.title || (isVideo ? "Video" : "Image")} Details
          </span>
          <Button
            variant="ghost"
            size="icon"
            onClick={onClose}
            className="h-8 w-8"
          >
            <X className="h-4 w-4" />
            <span className="sr-only">Close</span>
          </Button>
        </DialogTitle>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mt-4">
          <div className="space-y-4">
            {isVideo ? (
              <div className="relative aspect-video bg-muted rounded-md overflow-hidden">
                <video
                  src={mediaSrc}
                  controls
                  autoPlay={false}
                  className="w-full h-full object-contain"
                />
              </div>
            ) : (
              <div className="relative bg-muted rounded-md overflow-hidden">
                <img
                  src={mediaSrc}
                  alt={image.title || "Image"}
                  className="w-full max-h-[500px] object-contain"
                />
              </div>
            )}

            {image.type !== "url" && (
              <div className="text-sm text-muted-foreground">
                {image.width} × {image.height} pixels
                {isVideo && image.duration && (
                  <span> • {Math.floor(image.duration)} seconds</span>
                )}
                {image.actualFilePath && (
                  <div className="mt-1 break-all">
                    Path: {image.actualFilePath}
                  </div>
                )}
              </div>
            )}
          </div>

          <div className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="title">Title</Label>
              <Input
                id="title"
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                placeholder="Enter a title for this image"
              />
            </div>

            <Separator />

            {image.type !== "url" && (
              <div className="space-y-2">
                <Label>Pattern Tags</Label>
                <div className="flex flex-wrap gap-2 mb-2">
                  {patterns.map((pattern, index) => (
                    <Badge key={index} variant="secondary" className="gap-1">
                      {pattern.name}
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-4 w-4 ml-1 p-0"
                        onClick={() => removePattern(index)}
                      >
                        <X className="h-3 w-3" />
                        <span className="sr-only">Remove tag</span>
                      </Button>
                    </Badge>
                  ))}
                  {patterns.length === 0 && (
                    <div className="text-sm text-muted-foreground">
                      No pattern tags added yet
                    </div>
                  )}
                </div>

                <div className="flex gap-2">
                  <Input
                    placeholder="Add a new pattern tag"
                    value={newPattern}
                    onChange={(e) => setNewPattern(e.target.value)}
                    onKeyDown={(e) => e.key === "Enter" && addPattern()}
                  />
                  <Button onClick={addPattern} disabled={!newPattern.trim()}>
                    Add
                  </Button>
                </div>
              </div>
            )}

            <div className="flex justify-end gap-2 mt-4">
              <Button variant="ghost" onClick={onClose}>
                Cancel
              </Button>
              <Button onClick={handleSave}>Save Changes</Button>
            </div>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
};

export default ImageModal;
