
import React, { useEffect, useState, useRef } from "react";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { MediaItem, PatternTag } from "@/hooks/useImageStore";
import { X, ExternalLink, Scan, AlertCircle, Play, Video } from "lucide-react";
import { Button } from "@/components/ui/button";

interface ImageModalProps {
  isOpen: boolean;
  onClose: () => void;
  image: MediaItem | null;
}

const ImageModal: React.FC<ImageModalProps> = ({ isOpen, onClose, image }) => {
  const [videoError, setVideoError] = useState(false);
  const videoRef = useRef<HTMLVideoElement | null>(null);

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape" && isOpen) {
        onClose();
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isOpen, onClose]);

  // Reset video error when image changes
  useEffect(() => {
    setVideoError(false);
  }, [image]);

  if (!image) return null;

  const handleVideoError = () => {
    console.error("Failed to load video in modal:", image.id);
    if (image) {
      console.log("Video details in modal:", {
        id: image.id,
        type: image.type,
        url: image.url,
        actualFilePath: image.actualFilePath,
        fileExtension: image.fileExtension
      });
    }
    setVideoError(true);
  };

  const openExternalUrl = () => {
    if (image.type === "url" && image.sourceUrl) {
      window.open(image.sourceUrl, "_blank", "noopener,noreferrer");
    }
  };

  // Function to get the correct video URL
  const getVideoStreamUrl = (item: MediaItem): string => {
    // If we're running in Electron and have access to the stream endpoint
    if (typeof window.electron !== 'undefined' && item.id) {
      if (item.url.startsWith('app://video/')) {
        // For electron, try to use the stream endpoint
        try {
          if (typeof window.electron.getVideoStreamUrl === 'function') {
            return window.electron.getVideoStreamUrl(item.id);
          }
        } catch (error) {
          console.warn('Failed to get video stream URL:', error);
        }
      }
    }
    // Fallback to the original URL
    return item.url;
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

  const videoKey = image.type === "video" ? `video-${image.id}-${Date.now()}` : undefined;

  return (
    <Dialog open={isOpen} onOpenChange={(open) => !open && onClose()}>
      <DialogContent className="max-w-7xl w-[95vw] p-0 overflow-hidden bg-transparent border-none shadow-none max-h-[95vh]">
        <DialogTitle className="sr-only">
          {image.type === "url" ? "URL Preview" : image.type === "video" ? "Video Preview" : "Image Preview"}
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
              <>
                <div className="relative">
                  {videoError ? (
                    <div className="w-full min-w-[480px] min-h-[320px] bg-muted flex flex-col items-center justify-center rounded-md">
                      <Video className="w-12 h-12 text-muted-foreground mb-3" />
                      <p className="text-muted-foreground">Video playback failed</p>
                      <p className="text-xs text-muted-foreground mt-2">
                        {image.actualFilePath || image.url}
                      </p>
                    </div>
                  ) : (
                    <video
                      ref={videoRef}
                      className="max-h-[85vh] max-w-full object-contain rounded-md animate-scale-in shadow-md"
                      style={{ 
                        maxWidth: Math.min(image.width, window.innerWidth * 0.9),
                        maxHeight: Math.min(image.height, window.innerHeight * 0.85)
                      }}
                      controls
                      autoPlay
                      playsInline
                      onError={handleVideoError}
                      key={videoKey}
                    >
                      <source 
                        src={getVideoStreamUrl(image)} 
                        type={`video/${image.fileExtension || 'mp4'}`} 
                      />
                      Your browser does not support the video tag.
                    </video>
                  )}
                </div>
              </>
            ) : (
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
            )}
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
};

export default ImageModal;
