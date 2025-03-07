import React, { useState, useEffect, useRef } from "react";
import { ImageItem } from "@/hooks/useImageStore";
import { ExternalLink, Scan, Trash2, AlertCircle, Play, Pause, Video } from "lucide-react";
import { Button } from "@/components/ui/button";

interface ImageGridProps {
  images: ImageItem[];
  onImageClick: (image: ImageItem) => void;
  onImageDelete?: (id: string) => void;
}

const ImageGrid: React.FC<ImageGridProps> = ({ images, onImageClick, onImageDelete }) => {
  const [hoveredImageId, setHoveredImageId] = useState<string | null>(null);
  const [columns, setColumns] = useState(3);
  const videoRefs = useRef<{ [key: string]: HTMLVideoElement | null }>({});
  const videoCurrentTimes = useRef<{ [key: string]: number }>({});
  const [videoLoadErrors, setVideoLoadErrors] = useState<{ [key: string]: boolean }>({});

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
    if (hoveredImageId) {
      const videoElement = videoRefs.current[hoveredImageId];
      if (videoElement && !videoLoadErrors[hoveredImageId]) {
        videoElement.play().then(() => {
          // Playing successfully
        }).catch(error => {
          console.error("Error playing video:", error);
          setVideoLoadErrors(prev => ({...prev, [hoveredImageId]: true}));
        });
      }
    } else {
      Object.values(videoRefs.current).forEach(video => {
        if (video) {
          const id = Object.keys(videoRefs.current).find(
            key => videoRefs.current[key] === video
          );
          if (id) {
            videoCurrentTimes.current[id] = video.currentTime;
          }
          video.pause();
        }
      });
    }
  }, [hoveredImageId, videoLoadErrors]);

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

  const formatDuration = (seconds?: number): string => {
    if (!seconds) return "";
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs < 10 ? '0' : ''}${secs}`;
  };

  const handleImageClick = (image: ImageItem) => {
    if (image.type === "video") {
      const updatedImage = {
        ...image,
        currentTime: videoCurrentTimes.current[image.id] || 0
      };
      onImageClick(updatedImage);
    } else {
      onImageClick(image);
    }
  };

  const handleVideoError = (id: string) => {
    console.error(`Failed to load video: ${id}`);
    setVideoLoadErrors(prev => ({...prev, [id]: true}));
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
    } else if (item.type === "video") {
      return (
        <div className="relative">
          {videoLoadErrors[item.id] ? (
            <div className="w-full h-32 bg-muted flex items-center justify-center">
              <div className="flex flex-col items-center text-muted-foreground">
                <Video className="w-12 h-12 mb-2 opacity-40" />
                <span className="text-xs">Video format not supported</span>
              </div>
            </div>
          ) : (
            <video
              ref={el => videoRefs.current[item.id] = el}
              src={item.url}
              className="w-full h-auto object-cover rounded-t-lg"
              playsInline
              muted
              loop
              poster={item.thumbnailUrl}
              onError={() => handleVideoError(item.id)}
              onTimeUpdate={() => {
                if (videoRefs.current[item.id]) {
                  videoCurrentTimes.current[item.id] = videoRefs.current[item.id]!.currentTime;
                }
              }}
            />
          )}
          
          <div className="absolute inset-0 bg-black/40 flex items-center justify-center opacity-60 group-hover:opacity-0 transition-opacity">
            <Video className="w-12 h-12 text-white" />
          </div>
          
          {!hoveredImageId && (
            <div className="absolute bottom-2 right-2 bg-black/70 text-white text-xs px-2 py-1 rounded-md">
              {formatDuration(item.duration)}
            </div>
          )}
          
          {hoveredImageId === item.id && !videoLoadErrors[item.id] && (
            <div className="absolute bottom-0 left-0 right-0 p-2 bg-gradient-to-t from-black/60 to-transparent">
              <div className="flex items-center justify-between">
                <div className="text-white text-xs">
                  {formatDuration(item.duration)}
                </div>
                <div className="flex items-center text-white text-xs">
                  <Play className="w-3 h-3 mr-1" />
                  <span>Playing</span>
                </div>
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
    const columnArrays: ImageItem[][] = Array.from({ length: columns }, () => []);
    
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
                    onClick={() => handleImageClick(image)}
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
