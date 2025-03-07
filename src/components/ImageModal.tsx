import React, { useEffect, useRef, useState } from "react";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { ImageItem, PatternTag } from "@/hooks/useImageStore";
import { X, ExternalLink, Scan, AlertCircle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { getThumbnailPosition, getScaleTransform } from "@/lib/imageUtils";

interface ImageModalProps {
  isOpen: boolean;
  onClose: () => void;
  image: ImageItem | null;
  sourceElement: HTMLElement | null;
}

const ImageModal: React.FC<ImageModalProps> = ({ isOpen, onClose, image, sourceElement }) => {
  const contentRef = useRef<HTMLDivElement>(null);
  const [animationState, setAnimationState] = useState<"initial" | "animating-in" | "in" | "animating-out">("initial");
  const [startPosition, setStartPosition] = useState({ left: 0, top: 0, width: 0, height: 0 });
  
  useEffect(() => {
    if (isOpen && sourceElement) {
      const pos = getThumbnailPosition(sourceElement);
      setStartPosition(pos);
      setAnimationState("initial");
      
      // Force a reflow before starting the animation
      setTimeout(() => {
        setAnimationState("animating-in");
        setTimeout(() => {
          setAnimationState("in");
        }, 300);
      }, 10);
    } else if (!isOpen && animationState === "in") {
      setAnimationState("animating-out");
      setTimeout(() => {
        setAnimationState("initial");
      }, 300);
    }
  }, [isOpen, sourceElement, animationState]);

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape" && isOpen) {
        onClose();
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isOpen, onClose]);

  if (!image) return null;

  const openExternalUrl = () => {
    if (image.type === "url" && image.sourceUrl) {
      window.open(image.sourceUrl, "_blank", "noopener,noreferrer");
    }
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

  const getAnimationStyles = () => {
    if (contentRef.current && (animationState === "initial" || animationState === "animating-in")) {
      const transform = animationState === "initial" 
        ? getScaleTransform(startPosition, contentRef.current)
        : "translate(0,0) scale(1)";
      
      return {
        transform,
        opacity: animationState === "initial" ? 0 : 1,
        transition: animationState === "animating-in" ? "transform 0.3s ease-out, opacity 0.3s ease-out" : "none",
      };
    }
    
    if (animationState === "animating-out") {
      return {
        transform: getScaleTransform(startPosition, contentRef.current),
        opacity: 0,
        transition: "transform 0.3s ease-in, opacity 0.3s ease-in",
      };
    }
    
    return {};
  };

  return (
    <Dialog open={isOpen} onOpenChange={(open) => !open && onClose()}>
      <DialogContent className="max-w-7xl w-[95vw] p-0 overflow-hidden bg-transparent border-none shadow-none max-h-[95vh]">
        <DialogTitle className="sr-only">
          {image.type === "url" ? "URL Preview" : "Image Preview"}
        </DialogTitle>
        
        <div className="relative h-full w-full flex items-center justify-center">
          <button
            onClick={onClose}
            className="absolute top-4 right-4 bg-black/40 hover:bg-black/60 text-white rounded-full p-2 backdrop-blur-sm transition-all z-10"
            aria-label="Close"
          >
            <X className="h-5 w-5" />
          </button>
          
          <div 
            ref={contentRef}
            className="bg-white/5 backdrop-blur-lg p-4 rounded-lg overflow-hidden shadow-2xl max-h-[95vh] max-w-full"
            style={getAnimationStyles()}
          >
            {image.type === "url" ? (
              <div className="bg-card p-8 rounded-md shadow-md max-w-lg">
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
            ) : (
              <>
                <img
                  src={image.url}
                  alt="Enlarged screenshot"
                  className="max-h-[85vh] max-w-full object-contain rounded-md shadow-md"
                  style={{ 
                    maxWidth: Math.min(image.width || 1200, window.innerWidth * 0.9),
                    maxHeight: Math.min(image.height || 900, window.innerHeight * 0.85)
                  }}
                />
                
                <div className="mt-4 px-2">
                  {renderPatternTags(image.patterns, image.isAnalyzing, image.error)}
                </div>
              </>
            )}
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
};

export default ImageModal;
