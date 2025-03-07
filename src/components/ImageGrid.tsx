import React, { useState, useEffect, useRef } from "react";
import { MediaItem } from "@/hooks/useImageStore";
import { ExternalLink, Scan, Trash2, AlertCircle, Video } from "lucide-react";
import { Button } from "@/components/ui/button";

interface ImageGridProps {
  images: MediaItem[];
  onImageClick: (image: MediaItem) => void;
  onImageDelete?: (id: string) => void;
}

const ImageGrid: React.FC<ImageGridProps> = ({ images, onImageClick, onImageDelete }) => {
  const [hoveredImageId, setHoveredImageId] = useState<string | null>(null);
  const [columns, setColumns] = useState(3);
  const [videoErrors, setVideoErrors] = useState<Record<string, boolean>>({});
  const videoRefs = useRef<Record<string, HTMLVideoElement | null>>({});

  useEffect(() => {
    const updateColumns = () => {
      const width = window.innerWidth;
      if (width >= 1536) {
        setColumns(5); // 2xl breakpoint
      } else if (width >= 1280) {
        setColumns(4); // xl breakpoint
      } else if (width >= 1024) {
        setColumns(3); // lg breakpoint
      } else if (width >= 640) {
        setColumns(2); // sm breakpoint
      } else {
        setColumns(1); // xs/mobile
      }
    };

    updateColumns();
    window.addEventListener('resize', updateColumns);
    return () => window.removeEventListener('resize', updateColumns);
  }, []);

  useEffect(() => {
    setVideoErrors({});
  }, [images]);

  const handleVideoError = (id: string) => {
    console.error("Failed to load video:", id);
    const item = images.find(img => img.id === id);
    if (item) {
      console.log("Video details:", {
        id: item.id,
        type: item.type,
        url: item.url,
        actualFilePath: item.actualFilePath,
        fileExtension: item.fileExtension
      });
    }
    setVideoErrors(prev => ({...prev, [id]: true}));
  };

  const setVideoRef = (id: string, element: HTMLVideoElement | null) => {
    videoRefs.current[id] = element;
  };

  const renderPatternTags = (item: MediaItem) => {
    if (!item.patterns || item.patterns.length === 0) {
      if (item.isAnalyzing) {
        return (
          <div className="flex items-center gap-1 text-xs text-primary-foreground bg-primary/80 px-2 py-1 rounded-md">
            <Scan className="w-3 h-3 animate-pulse" />
            <span>Analyzing...</span>
          </div>
        );
      }
      if (item.error) {
        return (
          <div className="flex items-center gap-1 text-xs text-destructive-foreground bg-destructive/80 px-2 py-1 rounded-md">
            <AlertCircle className="w-3 h-3" />
            <span>Analysis failed</span>
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

  const renderItem = (item: MediaItem) => {
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
    } else if (item.type === "video") {
      return (
        <div className="relative">
          {videoErrors[item.id] ? (
            <div className="w-full aspect-video bg-muted flex flex-col items-center justify-center rounded-t-lg">
              <Video className="w-8 h-8 text-muted-foreground mb-2" />
              <span className="text-xs text-muted-foreground">Video preview unavailable</span>
            </div>
          ) : (
            <video 
              ref={(el) => setVideoRef(item.id, el)}
              className="w-full rounded-t-lg object-cover"
              poster=""
              preload="metadata"
              playsInline
              muted
              controls={hoveredImageId === item.id}
              onError={() => handleVideoError(item.id)}
              key={`${item.id}-${item.url}`}
            >
              <source 
                src={item.url} 
                type={`video/${item.fileExtension || 'mp4'}`} 
              />
            </video>
          )}
          {hoveredImageId === item.id && (
            <div className="absolute bottom-0 left-0 right-0 p-2 bg-gradient-to-t from-black/60 to-transparent">
              <div className="flex items-center gap-1 text-xs text-primary-foreground">
                <Video className="w-3 h-3" />
                <span>Video</span>
              </div>
            </div>
          )}
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
          {hoveredImageId === item.id && (
            <div className="absolute bottom-0 left-0 right-0 p-2 bg-gradient-to-t from-black/60 to-transparent">
              {renderPatternTags(item)}
            </div>
          )}
        </div>
      );
    }
  };

  const distributeImages = () => {
    const columnArrays: MediaItem[][] = Array.from({ length: columns }, () => []);
    
    images.forEach((image, index) => {
      const shortestColumnIndex = columnArrays
        .map((column, i) => ({ height: column.length, index: i }))
        .sort((a, b) => a.height - b.height)[0].index;
      
      columnArrays[shortestColumnIndex].push(image);
    });
    
    return columnArrays;
  };

  const columnData = distributeImages();

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
            Drag and drop images or videos anywhere, paste URLs, or use the upload buttons to add your first item.
          </p>
          <div className="mt-6 flex gap-3">
            <label 
              htmlFor="file-upload"
              className="inline-flex items-center px-4 py-2 bg-primary text-white rounded-lg hover:bg-primary/90 transition-colors cursor-pointer"
            >
              Upload media
            </label>
          </div>
        </div>
      ) : (
        <div className="masonry-grid">
          {columnData.map((column, columnIndex) => (
            <div 
              key={columnIndex} 
              className="masonry-column"
              style={{ width: `${100 / columns}%` }}
            >
              {column.map((image) => (
                <div key={image.id} className="masonry-item">
                  <div 
                    className="rounded-lg overflow-hidden bg-white shadow-sm hover:shadow-md transition-all relative group w-full"
                    onClick={() => onImageClick(image)}
                    onMouseEnter={() => setHoveredImageId(image.id)}
                    onMouseLeave={() => setHoveredImageId(null)}
                  >
                    {renderItem(image)}
                    
                    {onImageDelete && (
                      <Button
                        variant="destructive"
                        size="icon"
                        className="absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity p-1.5"
                        onClick={(e) => {
                          e.stopPropagation();
                          onImageDelete(image.id);
                        }}
                      >
                        <Trash2 className="h-4 w-4" />
                      </Button>
                    )}
                  </div>
                </div>
              ))}
            </div>
          ))}
        </div>
      )}
    </div>
  );
};

export default ImageGrid;
