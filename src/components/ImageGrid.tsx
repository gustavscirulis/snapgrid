
import React, { useEffect, useRef } from "react";
import { ImageItem } from "@/hooks/useImageStore";
import { calculateGridRowSpan } from "@/lib/imageUtils";

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
          <h3 className="text-2xl font-medium mb-2">No screenshots yet</h3>
          <p className="text-muted-foreground max-w-md">
            Drag and drop images anywhere on this page, or click the upload button to add your first screenshot.
          </p>
          <label 
            htmlFor="file-upload"
            className="mt-6 inline-flex items-center px-4 py-2 bg-primary text-white rounded-lg hover:bg-primary/90 transition-colors cursor-pointer"
          >
            Upload first image
          </label>
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
              <img
                src={image.url}
                alt="UI Screenshot"
                className="w-full h-auto object-cover"
                loading="lazy"
              />
            </div>
          ))}
        </div>
      )}
    </div>
  );
};

export default ImageGrid;
