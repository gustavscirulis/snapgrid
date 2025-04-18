import React from "react";
import { ExternalLink, X, Loader2 } from "lucide-react";
import { AnimatePresence, motion } from "framer-motion";
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { ImageItem } from "@/hooks/useImageStore";

interface LinkCardProps {
  item: ImageItem;
  onDelete?: (id: string) => void;
}

export const LinkCard: React.FC<LinkCardProps> = ({ item, onDelete }) => {
  const [isHovered, setIsHovered] = React.useState(false);

  const handleOpen = (e: React.MouseEvent) => {
    e.stopPropagation();
    // Open in default browser if Electron, otherwise fallback to window.open
    const url = (item.url ?? '').toString().trim();
    if (!url) {
      console.warn('LinkCard: Tried to open an empty or invalid URL:', item.url);
      return;
    }
    if (window && (window as any).electron && typeof (window as any).electron.openUrl === 'function') {
      (window as any).electron.openUrl(url);
    } else {
      window.open(url, "_blank", "noopener,noreferrer");
    }
  };


  // Prefer og:image, fallback to favicon, fallback to placeholder
  const hasThumbnail = !!item.ogImageUrl;
  const previewImg = item.ogImageUrl || item.faviconUrl || "https://placehold.co/400x200?text=No+Preview";

  return (
    <Card
      className="flex flex-col overflow-hidden group"
      onClick={handleOpen}
      title={item.url}
    >
      <div
        className="relative w-full aspect-[16/9] bg-gray-300 dark:bg-zinc-700 flex items-center justify-center group"
        onMouseEnter={() => setIsHovered(true)}
        onMouseLeave={() => setIsHovered(false)}
      >
        {item.ogImageUrl ? (
          <img
            src={item.ogImageUrl}
            alt={item.title || item.url}
            className="object-cover w-full h-full"
          />
        ) : (
          <div className="w-full h-full absolute inset-0 bg-gray-300 dark:bg-zinc-700 flex flex-col items-center justify-center">
            {item.faviconUrl && (
              <img
                src={item.faviconUrl}
                alt="Favicon"
                className="mb-2"
                style={{ width: 16, height: 16 }}
              />
            )}
            <span className="text-center text-xs font-medium text-black dark:text-white px-2 truncate w-full" title={item.title || item.url}>
              {item.title || item.url}
            </span>
          </div>
        )}
        {item.isAnalyzing && (
          <div className="absolute inset-0 flex items-center justify-center bg-black/40 z-20">
            <Loader2 className="w-5 h-5 animate-spin text-muted-foreground" />
          </div>
        )}
        {/* Overlay: Title & Description on hover above a gradient */}
        <AnimatePresence>
          {isHovered && item.ogImageUrl && (
            <motion.div
              className="absolute inset-0 pointer-events-none"
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: 10 }}
              transition={{ duration: 0.22 }}
            >
              <div className="absolute bottom-0 left-0 right-0 px-4 pb-3 pt-8 flex flex-col justify-end">
                <div className="absolute inset-x-0 bottom-0 h-20 bg-gradient-to-t from-black/80 to-transparent z-0" />
                <div className="relative z-10 flex flex-col gap-1">
                  {!item.isAnalyzing && (
                    <span className="text-white text-base font-medium truncate drop-shadow" title={item.title || item.url}>
                      {item.title || item.url}
                    </span>
                  )}
                  {item.isAnalyzing && !item.description ? (
                    <span className="text-white/90 text-xs truncate drop-shadow" title={item.url}>
                      {item.url}
                    </span>
                  ) : item.description ? (
                    <span className="text-white/90 text-xs truncate drop-shadow" title={item.description}>
                      {item.description}
                    </span>
                  ) : null}
                </div>
              </div>
            </motion.div>
          )}
        </AnimatePresence>
        {/* External link icon as badge at bottom right */}
        <div className="absolute bottom-2 right-2 bg-black/70 p-1 rounded text-white z-10 group-hover:opacity-100 opacity-80 transition-opacity">
          <ExternalLink className="w-4 h-4" />
        </div>
        {/* Delete (X) button, only visible on hover */}
        {onDelete && (
          <Button
            variant="ghost"
            size="icon"
            className="absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity p-1 rounded-full h-6 w-6 bg-black/60 text-white hover:text-white hover:bg-black/80 z-20"
            onClick={e => {
              e.stopPropagation();
              onDelete(item.id);
            }}
            title="Delete link"
          >
            <span className="sr-only">Delete link</span>
            <X className="h-3 w-3" />
          </Button>
        )}
      </div>

    </Card>
  );
};
