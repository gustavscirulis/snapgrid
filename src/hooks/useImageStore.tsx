
import { useState, useCallback, useEffect } from "react";
import { analyzeImage, hasApiKey } from "@/services/aiAnalysisService";
import { toast } from "sonner";
import { fetchUrlMetadata } from "@/lib/metadataUtils";
import { getImageDimensions, getVideoDimensions } from "@/lib/imageUtils";

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
  description?: string;
  thumbnailUrl?: string;
  sourceUrl?: string;
  patterns?: PatternTag[];
  isAnalyzing?: boolean;
  error?: string;
  filePath?: string;
  duration?: number;
}

export function useImageStore() {
  const [images, setImages] = useState<ImageItem[]>([]);
  const [isUploading, setIsUploading] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [isElectronAvailable, setIsElectronAvailable] = useState(false);

  useEffect(() => {
    const isElectronAvailable = window && 
      typeof window.electron !== 'undefined' && 
      window.electron !== null;
    
    setIsElectronAvailable(isElectronAvailable);
    
    const loadImages = async () => {
      try {
        if (isElectronAvailable) {
          console.log("Loading images from filesystem...");
          const loadedImages = await window.electron.loadImages();
          console.log("Loaded images:", loadedImages.length);
          setImages(loadedImages);
        } else {
          setImages([]);
        }
      } catch (error) {
        console.error("Error loading images:", error);
        toast.error("Failed to load images");
      }
      setIsLoading(false);
    };

    loadImages();
  }, []);

  const addImage = useCallback(async (file: File) => {
    if (!window.electron) {
      return;
    }
    
    setIsUploading(true);
    
    try {
      const dimensions = await getImageDimensions(file);
      
      // Create a temporary ID for the new image
      const newImageId = crypto.randomUUID();
      
      // Create a temporary item with loading state
      const newImage: ImageItem = {
        id: newImageId,
        type: "image",
        url: "",  // Will be set after file is saved
        width: dimensions.width,
        height: dimensions.height,
        createdAt: new Date(),
        isAnalyzing: hasApiKey(),
      };
      
      try {
        // Save the file first to get the real file path
        const result = await window.electron.saveImage({
          id: newImageId,
          file: file,
          metadata: {
            id: newImageId,
            type: newImage.type,
            width: newImage.width,
            height: newImage.height,
            createdAt: newImage.createdAt,
            isAnalyzing: newImage.isAnalyzing
          }
        });
        
        if (result.success && result.path) {
          console.log("Image saved successfully at:", result.path);
          
          // Create the final image object with the file path
          const finalImage = {
            ...newImage,
            url: `file://${result.path}`,
            filePath: result.path
          };
          
          // Add the image to the state
          setImages(prevImages => [finalImage, ...prevImages]);
          
          // If API key is available, analyze the image
          if (hasApiKey()) {
            try {
              const patterns = await analyzeImage(`file://${result.path}`);
              
              const imageWithPatterns = {
                ...finalImage,
                patterns: patterns.map(p => ({ name: p.pattern, confidence: p.confidence })),
                isAnalyzing: false
              };
              
              setImages(prevImages => {
                return prevImages.map(img => 
                  img.id === newImageId ? imageWithPatterns : img
                );
              });
              
              await window.electron.updateMetadata({
                id: imageWithPatterns.id,
                metadata: {
                  ...imageWithPatterns,
                  url: `file://${result.path}`
                }
              });
            } catch (error) {
              console.error("Failed to analyze image:", error);
              
              const errorMessage = error instanceof Error ? error.message : 'Unknown error occurred';
              setImages(prevImages => {
                return prevImages.map(img => 
                  img.id === newImageId ? { ...img, isAnalyzing: false, error: errorMessage } : img
                );
              });
              
              await window.electron.updateMetadata({
                id: newImageId,
                metadata: {
                  ...finalImage,
                  isAnalyzing: false,
                  error: errorMessage,
                }
              });
              
              toast.error("Failed to analyze image: " + errorMessage);
            }
          }
        } else {
          console.error("Failed to save image:", result.error);
          toast.error(`Failed to save image: ${result.error || "Unknown error"}`);
        }
      } catch (error) {
        console.error("Failed to save image to filesystem:", error);
        toast.error("Failed to save image to disk");
      }
    } catch (error) {
      console.error("Error getting image dimensions:", error);
      toast.error("Failed to process image");
    } finally {
      setIsUploading(false);
    }
  }, []);

  const addVideo = useCallback(async (file: File) => {
    if (!window.electron) {
      return;
    }
    
    setIsUploading(true);
    
    try {
      const videoInfo = await getVideoDimensions(file);
      
      // Create a temporary ID for the new video
      const newVideoId = crypto.randomUUID();
      
      // Create a temporary video object
      const newVideo: ImageItem = {
        id: newVideoId,
        type: "video",
        url: "",  // Will be set after file is saved
        width: videoInfo.width,
        height: videoInfo.height,
        duration: videoInfo.duration,
        createdAt: new Date(),
      };
      
      try {
        // Save the file first to get the real file path
        const result = await window.electron.saveVideo({
          id: newVideoId,
          file: file,
          metadata: {
            id: newVideoId,
            type: newVideo.type,
            width: newVideo.width,
            height: newVideo.height,
            duration: newVideo.duration,
            createdAt: newVideo.createdAt,
          }
        });
        
        if (result.success && result.path) {
          console.log("Video saved successfully at:", result.path);
          
          // Create the final video object with the file path
          const finalVideo = {
            ...newVideo,
            url: `file://${result.path}`,
            filePath: result.path
          };
          
          // Add the video to the state
          setImages(prevImages => [finalVideo, ...prevImages]);
          
          await window.electron.updateMetadata({
            id: finalVideo.id,
            metadata: {
              ...finalVideo,
              url: `file://${result.path}`
            }
          });
        } else {
          console.error("Failed to save video:", result.error);
          toast.error(`Failed to save video: ${result.error || "Unknown error"}`);
        }
      } catch (error) {
        console.error("Failed to save video to filesystem:", error);
        toast.error("Failed to save video to disk");
      }
    } catch (error) {
      console.error("Error getting video dimensions:", error);
      toast.error("Failed to process video");
    } finally {
      setIsUploading(false);
    }
  }, []);

  const addUrlCard = useCallback(async (url: string) => {
    if (!window.electron) {
      return;
    }
    
    setIsUploading(true);
    try {
      const initialCard: ImageItem = {
        id: crypto.randomUUID(),
        type: "url",
        url: url,
        width: 400,
        height: 400,
        createdAt: new Date(),
        title: url,
        sourceUrl: url,
        isAnalyzing: true
      };
      
      setImages(prevImages => [initialCard, ...prevImages]);
      
      try {
        const metadata = await fetchUrlMetadata(url);
        
        const updatedCard: ImageItem = {
          ...initialCard,
          isAnalyzing: false,
          title: metadata.title || url,
          description: metadata.description,
          thumbnailUrl: metadata.imageUrl || metadata.faviconUrl
        };
        
        setImages(prevImages => 
          prevImages.map(img => img.id === initialCard.id ? updatedCard : img)
        );
        
        try {
          await window.electron.saveUrlCard({
            id: updatedCard.id,
            metadata: updatedCard
          });
        } catch (error) {
          console.error("Failed to save URL card:", error);
          toast.error("Failed to save URL card to disk");
        }
      } catch (error) {
        console.error("Error fetching URL metadata:", error);
        
        setImages(prevImages => 
          prevImages.map(img => 
            img.id === initialCard.id 
              ? { ...img, isAnalyzing: false, error: "Failed to fetch metadata" } 
              : img
          )
        );
        
        try {
          await window.electron.saveUrlCard({
            id: initialCard.id,
            metadata: {
              ...initialCard,
              isAnalyzing: false,
              error: "Failed to fetch metadata"
            }
          });
        } catch (saveError) {
          console.error("Failed to save fallback URL card:", saveError);
          toast.error("Failed to save URL card to disk");
        }
      }
    } finally {
      setIsUploading(false);
    }
  }, []);

  const removeImage = useCallback(async (id: string) => {
    if (!window.electron) {
      return;
    }
    
    try {
      await window.electron.deleteImage(id);
      setImages(prevImages => prevImages.filter(img => img.id !== id));
      toast.success("Item deleted successfully");
    } catch (error) {
      console.error("Failed to delete item from filesystem:", error);
      toast.error("Failed to delete item from disk");
    }
  }, []);

  return {
    images,
    isUploading,
    isLoading,
    isElectronAvailable,
    addImage,
    addVideo,
    addUrlCard,
    removeImage,
  };
}
