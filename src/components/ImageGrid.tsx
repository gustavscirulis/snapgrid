
import React from "react";
import { ImageItem } from "@/hooks/useImageStore";
import { ExternalLink, Scan } from "lucide-react";

interface ImageGridProps {
  images: ImageItem[];
  onImageClick: (image: ImageItem) => void;
}

const ImageGrid: React.FC<ImageGridProps> = ({ images, onImageClick }) => {
  const renderPatternTags = (item: ImageItem) => {
    if (!item.patterns || item.patterns.length === 0) {
      if (item.isAnalyzing) {
        return (
          <div className="flex items-center gap-1 text-xs text-primary-foreground bg-primary/80 px-2 py-1 rounded-md">
            <Scan className="w-3 h-3 animate-pulse" />
            <span>Analyzing...</span>
          </div>
        );
      }
      return null;
    }

    return (
      <div className="flex flex-wrap gap-1 mt-2">
        {item.patterns.map((pattern, index) => (
          <span 
            key={index} 
            className="text-xs bg-secondary text-secondary-foreground px-2 py-0.5 rounded-md"
            title={`Confidence: ${Math.round(pattern.confidence * 100)}%`}
          >
            {pattern.name}
          </span>
        ))}
      </div>
    );
  };

  const renderItem = (item: ImageItem) => {
    if (item.type === "url") {
      return (
        <div className="url-card h-full flex flex-col">
          <div className="p-4 flex flex-col h-full">
            <div className="flex items-start gap-3">
              {item.thumbnailUrl && (
                <div className="w-12 h-12 bg-muted rounded-md overflow-hidden flex items-center justify-center flex-shrink-0">
                  <img 
                    src={item.thumbnailUrl} 
                    alt={item.title || "Website"} 
                    className="max-w-full max-h-full object-contain" 
                  />
                </div>
              )}
              <div className="flex-1 min-w-0">
                <h3 className="font-medium text-base mb-1 line-clamp-2">{item.title || item.url}</h3>
                <p className="text-xs text-muted-foreground truncate">{item.url}</p>
              </div>
            </div>
            <div className="mt-auto pt-3 flex items-center text-xs text-primary font-medium">
              <ExternalLink className="w-3 h-3 mr-1" />
              <span>Open URL</span>
            </div>
          </div>
        </div>
      );
    } else {
      return (
        <div className="relative">
          <img
            src={item.url}
            alt="UI Screenshot"
            className="w-full h-auto object-cover rounded-t-lg"
            loading="lazy"
          />
          <div className="absolute bottom-0 left-0 right-0 p-2 bg-gradient-to-t from-black/60 to-transparent">
            {renderPatternTags(item)}
          </div>
        </div>
      );
    }
  };

  return (
    <div className="px-4 py-6 w-full">
      {images.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <div className="w-24 h-24 bg-muted rounded-full flex items-center justify-center mb-6">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              className="h-10 w-10 text-muted-foreground"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
            >
              <rect x="3" y="3" width="18" height="18" rx="2" ry="2" />
              <circle cx="8.5" cy="8.5" r="1.5" />
              <polyline points="21 15 16 10 5 21" />
            </svg>
          </div>
          <h3 className="text-2xl font-medium mb-2">No items yet</h3>
          <p className="text-muted-foreground max-w-md">
            Drag and drop images anywhere, paste URLs, or use the upload buttons to add your first item.
          </p>
          <div className="mt-6 flex gap-3">
            <label 
              htmlFor="file-upload"
              className="inline-flex items-center px-4 py-2 bg-primary text-white rounded-lg hover:bg-primary/90 transition-colors cursor-pointer"
            >
              Upload image
            </label>
          </div>
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
          {images.map((image) => (
            <div
              key={image.id}
              className="rounded-lg overflow-hidden bg-white shadow-sm hover:shadow-md transition-all cursor-pointer"
              onClick={() => onImageClick(image)}
            >
              {renderItem(image)}
            </div>
          ))}
        </div>
      )}
    </div>
  );
};

export default ImageGrid;
