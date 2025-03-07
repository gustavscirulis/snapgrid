
import React from "react";
import { ImageItem } from "@/hooks/useImageStore";
import { Trash2 } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Video } from "lucide-react";
import { calculateGridRowSpan } from "@/lib/imageUtils";

interface ImageGridProps {
  images: ImageItem[];
  onImageClick: (image: ImageItem) => void;
  onImageDelete: (id: string) => void;
}

const ImageGrid: React.FC<ImageGridProps> = ({
  images,
  onImageClick,
  onImageDelete,
}) => {
  if (images.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center h-[50vh] text-center p-6">
        <div className="mb-4 bg-muted rounded-full p-3">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            width="24"
            height="24"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
            className="text-muted-foreground"
          >
            <path d="M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0"></path>
            <circle cx="9" cy="10" r="1"></circle>
            <circle cx="15" cy="10" r="1"></circle>
            <path d="M9.5 15a4 4 0 0 0 5 0"></path>
          </svg>
        </div>
        <h3 className="text-xl font-medium mb-2">No items yet</h3>
        <p className="text-muted-foreground max-w-md">
          Start adding items by dragging and dropping images, videos, or pasting URLs.
        </p>
      </div>
    );
  }

  // Helper function to get correct display source for images
  const getImageSrc = (image: ImageItem): string => {
    const isElectron = window && typeof window.electron !== 'undefined';
    
    if (image.type === "url") {
      return image.url;
    }
    
    // For images with actual file paths in Electron
    if (isElectron && image.actualFilePath) {
      // In development mode with Electron, we need to strip the file:// prefix
      // because the web security is disabled in dev mode
      return window.location.protocol === 'http:' 
        ? image.actualFilePath 
        : `file://${image.actualFilePath}`;
    }
    
    // Fallback to data URL
    return image.url;
  };

  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4 p-4">
      {images.map((image) => {
        // Determine what's displayed based on image type
        if (image.type === "url") {
          return (
            <Card
              key={image.id}
              className="relative overflow-hidden hover:shadow-md transition-shadow group cursor-pointer"
              onClick={() => onImageClick(image)}
            >
              <div className="p-4 flex items-center gap-3">
                {image.thumbnailUrl && (
                  <img
                    src={image.thumbnailUrl}
                    alt="Favicon"
                    className="w-6 h-6 rounded"
                  />
                )}
                <div className="flex-1 truncate">
                  <p className="font-medium truncate">{image.title || image.sourceUrl}</p>
                  <p className="text-xs text-muted-foreground truncate">
                    {image.sourceUrl}
                  </p>
                </div>
              </div>
              <div
                className="absolute top-1 right-1 opacity-0 group-hover:opacity-100 transition-opacity"
                onClick={(e) => {
                  e.stopPropagation();
                  onImageDelete(image.id);
                }}
              >
                <button
                  className="h-7 w-7 rounded-full bg-background/50 backdrop-blur-sm flex items-center justify-center hover:bg-background/80 transition-colors"
                  aria-label="Delete image"
                >
                  <Trash2 className="h-4 w-4 text-destructive" />
                </button>
              </div>
            </Card>
          );
        } else {
          const isVideo = image.type === "video";
          const displaySrc = isVideo 
            ? (image.thumbnailUrl || "") 
            : getImageSrc(image);
          
          // Video source is handled slightly differently
          const videoSrc = isVideo ? getImageSrc(image) : "";
          
          return (
            <Card
              key={image.id}
              className="relative overflow-hidden hover:shadow-md transition-shadow group cursor-pointer"
              onClick={() => onImageClick(image)}
            >
              <div className="relative aspect-square bg-muted">
                {image.isAnalyzing && (
                  <div className="absolute inset-0 flex items-center justify-center z-10 bg-background/80 backdrop-blur-sm">
                    <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
                  </div>
                )}
                {image.error && (
                  <div className="absolute inset-0 flex flex-col items-center justify-center z-10 bg-background/80 backdrop-blur-sm p-4">
                    <div className="text-destructive mb-2">Error analyzing</div>
                    <div className="text-xs text-muted-foreground text-center">{image.error}</div>
                  </div>
                )}
                {isVideo ? (
                  <>
                    <img
                      src={displaySrc}
                      alt={image.title || "Video thumbnail"}
                      className="h-full w-full object-cover"
                      onError={(e) => {
                        // Fallback for video thumbnails
                        e.currentTarget.src = 'data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"></path></svg>';
                        console.error("Failed to load video thumbnail:", displaySrc);
                      }}
                    />
                    <div className="absolute top-2 right-2 bg-background/50 backdrop-blur-sm p-1 rounded-md">
                      <Video className="h-4 w-4" />
                    </div>
                  </>
                ) : (
                  <img
                    src={displaySrc}
                    alt={image.title || "Uploaded image"}
                    className="h-full w-full object-cover"
                    onError={(e) => {
                      console.error("Failed to load image:", displaySrc);
                      e.currentTarget.src = 'data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"></path></svg>';
                    }}
                  />
                )}
              </div>
              {/* Pattern tags display */}
              {image.patterns && image.patterns.length > 0 && (
                <div className="p-2 text-xs flex flex-wrap gap-1 overflow-hidden max-h-16">
                  {image.patterns.slice(0, 3).map((pattern, index) => (
                    <span
                      key={index}
                      className="bg-muted px-1.5 py-0.5 rounded-sm"
                    >
                      {pattern.name}
                    </span>
                  ))}
                  {image.patterns.length > 3 && (
                    <span className="text-muted-foreground ml-1">
                      +{image.patterns.length - 3} more
                    </span>
                  )}
                </div>
              )}
              <div
                className="absolute top-1 right-1 opacity-0 group-hover:opacity-100 transition-opacity"
                onClick={(e) => {
                  e.stopPropagation();
                  onImageDelete(image.id);
                }}
              >
                <button
                  className="h-7 w-7 rounded-full bg-background/50 backdrop-blur-sm flex items-center justify-center hover:bg-background/80 transition-colors"
                  aria-label="Delete image"
                >
                  <Trash2 className="h-4 w-4 text-destructive" />
                </button>
              </div>
            </Card>
          );
        }
      })}
    </div>
  );
};

export default ImageGrid;
