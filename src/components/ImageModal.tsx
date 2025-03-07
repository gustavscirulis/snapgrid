import React, { useEffect, useRef, useState } from "react";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { ImageItem, PatternTag } from "@/hooks/useImageStore";
import { X, ExternalLink, Scan, AlertCircle, Play, Pause, FullscreenIcon, VideoOff } from "lucide-react";
import { Button } from "@/components/ui/button";

interface ImageModalProps {
  isOpen: boolean;
  onClose: () => void;
  image: ImageItem | null;
}

const ImageModal: React.FC<ImageModalProps> = ({ isOpen, onClose, image }) => {
  const videoRef = useRef<HTMLVideoElement>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [videoError, setVideoError] = useState(false);

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape" && isOpen) {
        onClose();
      } else if (e.key === " " && image?.type === "video") {
        togglePlayPause();
        e.preventDefault();
      } else if (e.key === "f" && image?.type === "video") {
        toggleFullscreen();
        e.preventDefault();
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isOpen, onClose, image]);

  useEffect(() => {
    if (isOpen && image?.type === "video" && videoRef.current) {
      setVideoError(false);
      
      if ('currentTime' in image && typeof image.currentTime === 'number') {
        videoRef.current.currentTime = image.currentTime;
      }
      
      videoRef.current.play().then(() => {
        setIsPlaying(true);
      }).catch(error => {
        console.error("Error playing video:", error);
        setVideoError(true);
        setIsPlaying(false);
      });
    }
    
    if (!isOpen) {
      setIsPlaying(false);
      setIsFullscreen(false);
    }
    
    const handleFullscreenChange = () => {
      setIsFullscreen(!!document.fullscreenElement);
    };
    
    document.addEventListener('fullscreenchange', handleFullscreenChange);
    return () => {
      document.removeEventListener('fullscreenchange', handleFullscreenChange);
    };
  }, [isOpen, image]);

  const togglePlayPause = () => {
    if (!videoRef.current || videoError) return;
    
    if (isPlaying) {
      videoRef.current.pause();
    } else {
      videoRef.current.play().catch(error => {
        console.error("Error playing video:", error);
        setVideoError(true);
      });
    }
    
    setIsPlaying(!isPlaying);
  };

  const toggleFullscreen = () => {
    if (!videoRef.current) return;
    
    if (!document.fullscreenElement) {
      videoRef.current.requestFullscreen();
    } else {
      document.exitFullscreen();
    }
  };

  const handleVideoError = () => {
    console.error("Video failed to load in modal");
    setVideoError(true);
    setIsPlaying(false);
  };

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

  const renderVideoControls = () => {
    if (image.type !== 'video' || videoError) return null;
    
    return (
      <div className="absolute bottom-4 left-0 right-0 mx-auto w-full max-w-md px-4 bg-black/50 backdrop-blur-sm rounded-full py-2 flex items-center justify-between">
        <Button
          variant="ghost"
          size="icon"
          className="text-white hover:bg-white/20"
          onClick={togglePlayPause}
        >
          {isPlaying ? (
            <Pause className="h-5 w-5" />
          ) : (
            <Play className="h-5 w-5" />
          )}
        </Button>
        
        <Button
          variant="ghost"
          size="icon"
          className="text-white hover:bg-white/20"
          onClick={toggleFullscreen}
        >
          <FullscreenIcon className="h-5 w-5" />
        </Button>
      </div>
    );
  };

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
                    <span className="font-medium text-xl mb-2 block">{image.title || "Website"}</span>
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
              <div className="relative">
                {videoError ? (
                  <div className="flex flex-col items-center justify-center bg-black/80 p-8 rounded-lg">
                    <VideoOff className="w-16 h-16 text-muted-foreground mb-4" />
                    <p className="text-white/80 text-center">
                      This video format is not supported by your browser or the file couldn't be loaded.
                    </p>
                    <p className="text-white/60 text-sm mt-2">
                      Try reopening the app or converting the video to a different format.
                    </p>
                  </div>
                ) : (
                  <video
                    ref={videoRef}
                    src={image.url}
                    className="max-h-[85vh] max-w-full rounded-md animate-scale-in shadow-md"
                    style={{ 
                      maxWidth: Math.min(image.width, window.innerWidth * 0.9),
                      maxHeight: Math.min(image.height, window.innerHeight * 0.85)
                    }}
                    controls={false}
                    playsInline
                    onPlay={() => setIsPlaying(true)}
                    onPause={() => setIsPlaying(false)}
                    onError={handleVideoError}
                  />
                )}
                
                {renderVideoControls()}
              </div>
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
