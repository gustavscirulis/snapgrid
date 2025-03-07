
import React, { useEffect, useRef } from "react";
import { Dialog, DialogContent, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { ImageItem, PatternTag } from "@/hooks/useImageStore";
import { X, ExternalLink, Scan, AlertCircle, RefreshCw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { analyzeImage } from "@/services/aiAnalysisService";
import { toast } from "sonner";

interface ImageModalProps {
  isOpen: boolean;
  onClose: () => void;
  image: ImageItem | null;
  onImageUpdate?: (updatedImage: ImageItem) => void;
}

const ImageModal: React.FC<ImageModalProps> = ({ 
  isOpen, 
  onClose, 
  image,
  onImageUpdate
}) => {
  const videoRef = useRef<HTMLVideoElement>(null);
  const currentTimeRef = useRef<number>(0);

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape" && isOpen) {
        onClose();
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isOpen, onClose]);

  // Save current time when video is played in modal
  const handleTimeUpdate = () => {
    if (videoRef.current) {
      currentTimeRef.current = videoRef.current.currentTime;
    }
  };

  // Set current time when modal is opened
  useEffect(() => {
    if (isOpen && image?.type === "video" && videoRef.current) {
      // Small timeout to ensure the video element is fully loaded
      const timer = setTimeout(() => {
        if (videoRef.current) {
          videoRef.current.currentTime = currentTimeRef.current;
          videoRef.current.play().catch(error => {
            console.error("Failed to play video in modal:", error);
          });
        }
      }, 100);
      return () => clearTimeout(timer);
    }
  }, [isOpen, image]);

  if (!image) return null;

  const openExternalUrl = () => {
    if (image.type === "url" && image.sourceUrl) {
      window.open(image.sourceUrl, "_blank", "noopener,noreferrer");
    }
  };

  const handleRetryAnalysis = async () => {
    if (!image || image.type !== "image" || !onImageUpdate) return;
    
    // Update image to analyzing state
    const updatingImage = {
      ...image,
      isAnalyzing: true,
      error: undefined
    };
    onImageUpdate(updatingImage);
    
    try {
      const patterns = await analyzeImage(image.url);
      
      const updatedImage = {
        ...image,
        patterns: patterns.map(p => ({ name: p.pattern, confidence: p.confidence })),
        isAnalyzing: false,
        error: undefined
      };
      
      onImageUpdate(updatedImage);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error occurred';
      
      const failedImage = {
        ...image,
        isAnalyzing: false,
        error: errorMessage
      };
      
      onImageUpdate(failedImage);
      toast.error("Failed to analyze image: " + errorMessage);
    }
  };

  const renderPatternTags = (patterns?: PatternTag[], isAnalyzing?: boolean, error?: string) => {
    // Don't show pattern UI for videos
    if (image.type === "video") {
      return null;
    }
    
    if (!patterns || patterns.length === 0) {
      if (isAnalyzing) {
        return (
          <div className="flex items-center gap-2 text-sm bg-primary/10 px-3 py-2 rounded-md">
            <Scan className="w-4 h-4 animate-pulse text-primary" />
            <span>Analyzing UI patterns...</span>
          </div>
        );
      }

      if (error) {
        return (
          <div className="flex flex-col gap-2">
            <div className="flex items-center gap-2 text-sm bg-destructive/10 px-3 py-2 rounded-md">
              <AlertCircle className="w-4 h-4 text-destructive" />
              <span>Analysis failed: {error}</span>
            </div>
            {onImageUpdate && (
              <Button 
                size="sm" 
                className="mt-2"
                onClick={handleRetryAnalysis}
              >
                <RefreshCw className="w-4 h-4 mr-2" />
                Retry Analysis
              </Button>
            )}
          </div>
        );
      }

      return (
        <div className="flex items-center gap-2 text-sm bg-muted/50 px-3 py-2 rounded-md">
          <span>No UI patterns detected. Set an OpenAI API key to enable analysis.</span>
        </div>
      );
    }

    return (
      <div className="flex flex-wrap gap-2">
        {patterns.map((pattern, index) => (
          <div 
            key={index} 
            className="text-sm bg-primary/20 text-primary px-3 py-1.5 rounded-md"
          >
            {pattern.name}
          </div>
        ))}
      </div>
    );
  };

  return (
    <Dialog open={isOpen} onOpenChange={(open) => !open && onClose()}>
      <DialogContent className="max-w-7xl w-[95vw] p-0 overflow-hidden bg-transparent border-none shadow-none max-h-[95vh]">
        <DialogTitle className="sr-only">
          {image?.type === "url" ? "URL Preview" : image?.type === "video" ? "Video Preview" : "Image Preview"}
        </DialogTitle>
        <DialogDescription className="sr-only">
          {image?.type === "url" 
            ? "View details about this URL" 
            : image?.type === "video" 
              ? "View this video in full screen" 
              : "View this image in full screen and check detected UI patterns"}
        </DialogDescription>
        
        <div className="relative h-full w-full flex items-center justify-center">
          <button
            onClick={onClose}
            className="absolute top-4 right-4 bg-black/40 hover:bg-black/60 text-white rounded-full p-2 backdrop-blur-sm transition-all z-10"
            aria-label="Close"
          >
            <X className="h-5 w-5" />
          </button>
          
          <div className="bg-white/5 backdrop-blur-lg p-4 rounded-lg overflow-hidden shadow-2xl max-h-[95vh] max-w-full">
            {image.type === "url" ? (
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
            ) : image.type === "video" ? (
              <div className="flex flex-col">
                <video
                  ref={videoRef}
                  src={image.url}
                  controls
                  onTimeUpdate={handleTimeUpdate}
                  className="max-h-[85vh] max-w-full object-contain rounded-md animate-scale-in shadow-md"
                  style={{ 
                    maxWidth: Math.min(image.width, window.innerWidth * 0.9),
                    maxHeight: Math.min(image.height, window.innerHeight * 0.85)
                  }}
                  autoPlay
                >
                  Your browser does not support the video tag.
                </video>
              </div>
            ) : (
              <div className="flex flex-col">
                <img
                  src={image.url}
                  alt="Enlarged screenshot"
                  className="max-h-[85vh] max-w-full object-contain rounded-md animate-scale-in shadow-md"
                  style={{ 
                    maxWidth: Math.min(image.width, window.innerWidth * 0.9),
                    maxHeight: Math.min(image.height, window.innerHeight * 0.85)
                  }}
                />
                
                <div className="mt-4 px-2 max-w-full overflow-x-auto">
                  {renderPatternTags(image.patterns, image.isAnalyzing, image.error)}
                </div>
              </div>
            )}
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
};

export default ImageModal;
