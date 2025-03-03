
import React, { useEffect, useRef } from "react";
import { ImageItem, ImageItemType } from "@/hooks/useImageStore";
import { calculateGridRowSpan } from "@/lib/imageUtils";
import { ExternalLink } from "lucide-react";

interface ImageGridProps {
  images: ImageItem[];
  onImageClick: (image: ImageItem) => void;
}

const ImageGrid: React.FC<ImageGridProps> = ({ images, onImageClick }) => {
  const gridRef = useRef<HTMLDivElement>(null);

  // Resize the grid items to create a masonry layout
  useEffect(() => {
    const resizeGridItems = () => {
      const grid = gridRef.current;
      if (!grid) return;

      const items = grid.querySelectorAll(".masonry-item");
      items.forEach((item) => {
        const dataHeight = item.getAttribute("data-height");
        const dataWidth = item.getAttribute("data-width");
        
        if (dataHeight && dataWidth) {
          const height = parseInt(dataHeight);
          const width = parseInt(dataWidth);
          const rowSpan = calculateGridRowSpan(height, width);
          (item as HTMLElement).style.gridRowEnd = `span ${rowSpan}`;
        }
      });
    };

    // Initialize
    resizeGridItems();
    
    // Add event listener for window resize
    window.addEventListener("resize", resizeGridItems);
    
    // Cleanup
    return () => {
      window.removeEventListener("resize", resizeGridItems);
    };
  }, [images]);

  const renderItem = (item: ImageItem) => {
    if (item.type === "url") {
      return (
        <div className="url-card flex flex-col h-full">
          <div className="flex-1 p-4 flex flex-col">
            {item.thumbnailUrl && (
              <div className="w-16 h-16 bg-muted rounded-md mb-3 overflow-hidden flex items-center justify-center">
                <img 
                  src={item.thumbnailUrl} 
                  alt={item.title || "Website"} 
                  className="max-w-full max-h-full object-contain" 
                />
              </div>
            )}
            <h3 className="font-medium text-base mb-2 line-clamp-2">{item.title || item.url}</h3>
            <p className="text-xs text-muted-foreground truncate mb-2">{item.url}</p>
            <div className="flex-grow"></div>
            <div className="flex items-center text-xs text-primary font-medium">
              <ExternalLink className="w-3 h-3 mr-1" />
              <span>Open URL</span>
            </div>
          </div>
        </div>
      );
    } else {
      return (
        <img
          src={item.url}
          alt="UI Screenshot"
          className="w-full h-auto object-cover"
          loading="lazy"
        />
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
        <div className="masonry-grid" ref={gridRef}>
          {images.map((image) => (
            <div
              key={image.id}
              className="masonry-item rounded-lg overflow-hidden bg-white shadow-sm hover:shadow-md transition-all cursor-pointer"
              data-height={image.height}
              data-width={image.width}
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
