
import React, { useEffect, useRef } from "react";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { ImageItem, PatternTag } from "@/hooks/useImageStore";
import { X, ExternalLink, Scan, AlertCircle } from "lucide-react";
import { Button } from "@/components/ui/button";

interface ImageModalProps {
  isOpen: boolean;
  onClose: () => void;
  image: ImageItem | null;
}

const ImageModal: React.FC<ImageModalProps> = ({ isOpen, onClose, image }) => {
  const videoRef = useRef<HTMLVideoElement>(null);
  const isElectron = Boolean(window?.electron);

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape" && isOpen) {
        onClose();
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isOpen, onClose]);

  useEffect(() => {
    if (!isOpen && videoRef.current) {
      videoRef.current.pause();
    }

    if (isOpen && image?.type === 'video' && videoRef.current) {
      videoRef.current.play().catch(err => {
        console.error("Error playing video:", err);
      });
    }
  }, [isOpen, image]);

  if (!image) return null;

  const openExternalUrl = () => {
    if (image.type === "url" && image.sourceUrl) {
      window.open(image.sourceUrl, "_blank", "noopener,noreferrer");
    }
  };

  const getVideoSource = () => {
    if (isElectron && image.actualFilePath) {
      // Get the actual path from the filesystem
      let filePath = image.actualFilePath;
      
      // Check if the file path has the correct extension
      const pathExtension = filePath.split('.').pop();
      if (image.fileExtension && pathExtension !== image.fileExtension) {
        console.warn(`Path extension (${pathExtension}) doesn't match file type (${image.fileExtension})`);
        // Replace the extension with the correct one
        filePath = filePath.replace(`.${pathExtension}`, `.${image.fileExtension}`);
        console.log("Corrected video file path:", filePath);
      }
      
      console.log("Using actual file path for video:", filePath);
      console.log("File extension:", image.fileExtension);
      return `file://${filePath}`;
    }
    console.log("Using data URL for video (browser mode or missing path)");
    return image.url;
  };

  const renderPatternTags = (patterns?: PatternTag[], isAnalyzing?: boolean, error?: string) => {
    if (!patterns || patterns.length === 0) {
      if (isAnalyzing) {
        return (
          <div className="flex items-center gap-2 text-sm bg-primary/10 px-3 py-2 rounded-md mt-4">
            <Scan className="w-4 h-4 animate-pulse text-primary" />
            <span>Analyzing UI patterns...</span>
          </div>
        );
      }

      if (error) {
        return (
          <div className="flex items-center gap-2 text-sm bg-destructive/10 px-3 py-2 rounded-md mt-4">
            <AlertCircle className="w-4 h-4 text-destructive" />
            <span>Analysis failed: {error}</span>
          </div>
        );
      }

      return (
        <div className="flex items-center gap-2 text-sm bg-muted/50 px-3 py-2 rounded-md mt-4">
          <span>No UI patterns detected. Set an OpenAI API key to enable analysis.</span>
        </div>
      );
    }

    return (
      <div className="mt-4">
        <h4 className="text-sm font-medium mb-2 text-white/80">Detected UI Patterns</h4>
        <div className="flex flex-wrap gap-2">
          {patterns.map((pattern, index) => (
            <div 
              key={index} 
              className="text-sm bg-primary/20 text-white px-3 py-1.5 rounded-md flex items-center gap-1"
            >
              <span>{pattern.name}</span>
              <span className="text-xs bg-white/20 px-1.5 py-0.5 rounded-full">
                {Math.round(pattern.confidence * 100)}%
              </span>
            </div>
          ))}
        </div>
      </div>
    );
  };

  const renderContent = () => {
    if (image.type === "url") {
      return (
        <div className="bg-card p-8 rounded-md shadow-md animate-scale-in max-w-lg">
          <div className="flex items-start mb-6">
            {image.thumbnailUrl && (
              <div className="w-16 h-16 bg-muted rounded-md mr-4 overflow-hidden flex items-center justify-center">
                <img 
                  src={image.thumbnailUrl} 
                  alt={image.title || "Website"} 
                  className="max-w-full max-h-full object-contain" 
                />
              </div>
            )}
            <div>
              <h3 className="font-medium text-xl mb-2">{image.title || "Website"}</h3>
              <p className="text-sm text-muted-foreground break-all">{image.url}</p>
            </div>
          </div>
          <Button 
            className="w-full" 
            onClick={openExternalUrl}
          >
            <ExternalLink className="w-4 h-4 mr-2" />
            Open URL
          </Button>
        </div>
      );
    } else if (image.type === "video") {
      return (
        <>
          <div className="relative">
            <video
              ref={videoRef}
              src={getVideoSource()}
              controls
              autoPlay
              className="max-h-[85vh] max-w-full object-contain rounded-md animate-scale-in shadow-md"
              style={{ 
                maxWidth: Math.min(image.width, window.innerWidth * 0.9),
                maxHeight: Math.min(image.height, window.innerHeight * 0.85)
              }}
            />
          </div>
          
          {image.duration && (
            <div className="mt-4 px-2">
              <div className="flex items-center gap-2 text-sm bg-muted/50 px-3 py-2 rounded-md">
                <span>Duration: {formatDuration(image.duration)}</span>
              </div>
            </div>
          )}
        </>
      );
    } else {
      return (
        <>
          <img
            src={image.url}
            alt="Enlarged screenshot"
            className="max-h-[85vh] max-w-full object-contain rounded-md animate-scale-in shadow-md"
            style={{ 
              maxWidth: Math.min(image.width, window.innerWidth * 0.9),
              maxHeight: Math.min(image.height, window.innerHeight * 0.85)
            }}
          />
          
          <div className="mt-4 px-2">
            {renderPatternTags(image.patterns, image.isAnalyzing, image.error)}
          </div>
        </>
      );
    }
  };

  const formatDuration = (seconds: number): string => {
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  };

  return (
    <Dialog open={isOpen} onOpenChange={(open) => !open && onClose()}>
      <DialogContent className="max-w-7xl w-[95vw] p-0 overflow-hidden bg-transparent border-none shadow-none max-h-[95vh]">
        <DialogTitle className="sr-only">
          {image.type === "url" ? "URL Preview" : (image.type === "video" ? "Video Player" : "Image Preview")}
        </DialogTitle>
        
        <div className="relative h-full w-full flex items-center justify-center">
          <button
            onClick={onClose}
            className="absolute top-4 right-4 bg-black/40 hover:bg-black/60 text-white rounded-full p-2 backdrop-blur-sm transition-all z-10"
            aria-label="Close"
          >
            <X className="h-5 w-5" />
          </button>
          
          <div className="bg-white/5 backdrop-blur-lg p-4 rounded-lg overflow-hidden shadow-2xl max-h-[95vh] max-w-full">
            {renderContent()}
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
};

export default ImageModal;
