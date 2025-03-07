import { useState, useCallback, useEffect } from "react";
import { analyzeImage, hasApiKey } from "@/services/aiAnalysisService";
import { toast } from "sonner";
import { generateVideoThumbnail } from "@/lib/imageUtils";

export type ImageItemType = "image" | "url" | "video";

export interface PatternTag {
  name: string;
  confidence: number;
}

export interface ImageItem {
  id: string;
  type: ImageItemType;
  url: string;
  width: number;
  height: number;
  createdAt: Date;
  title?: string;
  thumbnailUrl?: string;
  sourceUrl?: string;
  patterns?: PatternTag[];
  isAnalyzing?: boolean;
  error?: string;
  actualFilePath?: string;
  duration?: number; // For videos
}

interface DeletedImage {
  item: ImageItem;
  timestamp: number;
}

export function useImageStore() {
  const [images, setImages] = useState<ImageItem[]>([]);
  const [isUploading, setIsUploading] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [isElectron, setIsElectron] = useState(false);
  const [lastDeletedImage, setLastDeletedImage] = useState<DeletedImage | null>(null);

  useEffect(() => {
    const isRunningInElectron = window && 
      typeof window.electron !== 'undefined' && 
      window.electron !== null;
    
    console.log("useImageStore - Electron detection:", {
      electronExists: typeof window.electron !== 'undefined',
      electronValue: window.electron
    });
    
    setIsElectron(isRunningInElectron);
    
    const loadImages = async () => {
      try {
        if (isRunningInElectron) {
          console.log("Loading images from filesystem...");
          const loadedImages = await window.electron.loadImages();
          console.log("Loaded images:", loadedImages.length);
          setImages(loadedImages);
        } else {
          setImages([]);
          toast.warning("Running in browser mode. Images will not be saved permanently.");
        }
      } catch (error) {
        console.error("Error loading images:", error);
        toast.error("Failed to load images");
      }
      setIsLoading(false);
    };

    loadImages();

    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'z') {
        undoLastDeletedImage();
      }
    };
    
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, []);

  const updateImageItem = useCallback((updatedImage: ImageItem) => {
    setImages(prevImages => {
      const updated = prevImages.map(img => 
        img.id === updatedImage.id ? updatedImage : img
      );
      
      if (isElectron) {
        try {
          if (updatedImage.type === "image" || updatedImage.type === "video") {
            window.electron.saveImage({
              id: updatedImage.id,
              dataUrl: updatedImage.url,
              metadata: {
                ...updatedImage,
                url: undefined
              }
            });
          }
        } catch (error) {
          console.error("Failed to update image metadata:", error);
        }
      }
      
      return updated;
    });
  }, [isElectron]);

  const addImage = useCallback(async (file: File) => {
    setIsUploading(true);
    
    const isVideo = file.type.startsWith('video/');
    
    try {
      if (isVideo) {
        const thumbnailUrl = await generateVideoThumbnail(file);
        const videoElement = document.createElement('video');
        
        await new Promise<void>((resolve, reject) => {
          videoElement.onloadedmetadata = () => resolve();
          videoElement.onerror = () => reject(new Error("Failed to load video metadata"));
          videoElement.src = URL.createObjectURL(file);
        });
        
        const newVideo: ImageItem = {
          id: crypto.randomUUID(),
          type: "video",
          url: URL.createObjectURL(file),
          thumbnailUrl: thumbnailUrl,
          width: videoElement.videoWidth,
          height: videoElement.videoHeight,
          createdAt: new Date(),
          title: file.name,
          duration: videoElement.duration
        };
        
        const reader = new FileReader();
        reader.onload = async (e) => {
          if (!e.target?.result) {
            setIsUploading(false);
            return;
          }
          
          newVideo.url = e.target.result as string;
          
          const updatedVideos = [newVideo, ...images];
          setImages(updatedVideos);
          
          if (isElectron) {
            try {
              await window.electron.saveImage({
                id: newVideo.id,
                dataUrl: newVideo.url,
                metadata: {
                  ...newVideo,
                  url: undefined
                }
              });
              toast.success("Video saved successfully");
            } catch (error) {
              console.error("Failed to save video:", error);
              toast.error("Failed to save video");
            }
          }
        };
        
        reader.readAsDataURL(file);
      } else {
        const reader = new FileReader();
        reader.onload = async (e) => {
          if (!e.target?.result) {
            setIsUploading(false);
            return;
          }

          const img = new Image();
          img.onload = async () => {
            const newImage: ImageItem = {
              id: crypto.randomUUID(),
              type: "image",
              url: e.target?.result as string,
              width: img.width,
              height: img.height,
              createdAt: new Date(),
              isAnalyzing: hasApiKey(),
            };
            
            const updatedImages = [newImage, ...images];
            setImages(updatedImages);
            
            if (isElectron) {
              try {
                console.log("Saving image to filesystem:", newImage.id);
                const result = await window.electron.saveImage({
                  id: newImage.id,
                  dataUrl: newImage.url,
                  metadata: {
                    id: newImage.id,
                    type: newImage.type,
                    width: newImage.width,
                    height: newImage.height,
                    createdAt: newImage.createdAt,
                    isAnalyzing: newImage.isAnalyzing
                  }
                });
                
                if (result.success && result.path) {
                  console.log("Image saved successfully at:", result.path);
                  newImage.actualFilePath = result.path;
                  setImages([newImage, ...images.filter(img => img.id !== newImage.id)]);
                  
                  toast.success("Image saved successfully");
                } else {
                  console.error("Failed to save image:", result.error);
                  toast.error("Failed to save image");
                }
              } catch (error) {
                console.error("Failed to save image to filesystem:", error);
                toast.error("Failed to save image to disk");
              }
            } else {
              toast.info("Running in browser mode. Image is only stored in memory.");
            }
            
            if (hasApiKey()) {
              try {
                const patterns = await analyzeImage(newImage.url);
                
                const imageWithPatterns = {
                  ...newImage,
                  patterns: patterns.map(p => ({ name: p.pattern, confidence: p.confidence })),
                  isAnalyzing: false
                };
                
                updateImageItem(imageWithPatterns);
              } catch (error) {
                console.error("Failed to analyze image:", error);
                
                const errorMessage = error instanceof Error ? error.message : 'Unknown error occurred';
                
                const imageWithError = {
                  ...newImage,
                  isAnalyzing: false,
                  error: errorMessage
                };
                
                updateImageItem(imageWithError);
                toast.error("Failed to analyze image: " + errorMessage);
              }
            }
          };
          img.src = e.target?.result as string;
        };
        
        reader.readAsDataURL(file);
      }
    } catch (error) {
      console.error("Error processing file:", error);
      toast.error("Failed to process file");
    } finally {
      setIsUploading(false);
    }
  }, [images, isElectron, updateImageItem]);

  const addUrlCard = useCallback(async (url: string) => {
    setIsUploading(true);
    try {
      const metadata = await fetchUrlMetadata(url);
      
      const newCard: ImageItem = {
        id: crypto.randomUUID(),
        type: "url",
        url: url,
        width: 400,
        height: 120,
        createdAt: new Date(),
        title: metadata.title || url,
        thumbnailUrl: metadata.thumbnailUrl,
        sourceUrl: url
      };
      
      const updatedImages = [newCard, ...images];
      setImages(updatedImages);
      
      if (isElectron) {
        try {
          await window.electron.saveUrlCard({
            id: newCard.id,
            metadata: newCard
          });
          toast.success(`URL card saved to disk`);
        } catch (error) {
          console.error("Failed to save URL card:", error);
          toast.error("Failed to save URL card to disk");
        }
      } else {
        toast.info("Running in browser mode. URL card is only stored in memory.");
      }
    } catch (error) {
      console.error("Error adding URL card:", error);
      
      const fallbackCard: ImageItem = {
        id: crypto.randomUUID(),
        type: "url",
        url: url,
        width: 400,
        height: 120,
        createdAt: new Date(),
        title: url,
        sourceUrl: url
      };
      
      const updatedImages = [fallbackCard, ...images];
      setImages(updatedImages);
      
      if (isElectron) {
        try {
          await window.electron.saveUrlCard({
            id: fallbackCard.id,
            metadata: fallbackCard
          });
        } catch (saveError) {
          console.error("Failed to save fallback URL card:", saveError);
          toast.error("Failed to save URL card to disk");
        }
      }
    } finally {
      setIsUploading(false);
    }
  }, [images, isElectron]);

  const undoLastDeletedImage = useCallback(async () => {
    if (!lastDeletedImage) return;
    
    try {
      const deletedItem = lastDeletedImage.item;
      
      setImages(prev => [deletedItem, ...prev]);
      
      if (isElectron && (deletedItem.type === "image" || deletedItem.type === "video")) {
        try {
          await window.electron.saveImage({
            id: deletedItem.id,
            dataUrl: deletedItem.url,
            metadata: {
              ...deletedItem,
              url: undefined
            }
          });
        } catch (error) {
          console.error("Failed to restore image to filesystem:", error);
          toast.error("Failed to restore image to disk");
        }
      } else if (isElectron && deletedItem.type === "url") {
        try {
          await window.electron.saveUrlCard({
            id: deletedItem.id,
            metadata: deletedItem
          });
        } catch (error) {
          console.error("Failed to restore URL card:", error);
          toast.error("Failed to restore URL card to disk");
        }
      }
      
      setLastDeletedImage(null);
      
      toast.success("Successfully restored item");
    } catch (error) {
      console.error("Failed to undo delete:", error);
      toast.error("Failed to restore deleted item");
    }
  }, [lastDeletedImage, isElectron]);

  const removeImage = useCallback(async (id: string) => {
    const imageToDelete = images.find(img => img.id === id);
    if (!imageToDelete) return;
    
    setLastDeletedImage({
      item: imageToDelete,
      timestamp: Date.now()
    });
    
    if (isElectron) {
      try {
        await window.electron.deleteImage(id);
      } catch (error) {
        console.error("Failed to delete image from filesystem:", error);
      }
    }
    
    const updatedImages = images.filter(img => img.id !== id);
    setImages(updatedImages);
    
    toast.success("Item deleted", {
      action: {
        label: "Undo",
        onClick: undoLastDeletedImage
      }
    });
  }, [images, isElectron, undoLastDeletedImage]);

  return {
    images,
    isUploading,
    isLoading,
    addImage,
    addUrlCard,
    removeImage,
    updateImageItem,
    undoLastDeletedImage
  };
}

async function fetchUrlMetadata(url: string): Promise<{ title?: string; thumbnailUrl?: string }> {
  try {
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    const domain = new URL(url).hostname;
    const thumbnailUrl = `https://www.google.com/s2/favicons?domain=${domain}&sz=128`;
    
    return {
      title: domain,
      thumbnailUrl
    };
  } catch (error) {
    console.error("Error fetching URL metadata:", error);
    return {};
  }
}
