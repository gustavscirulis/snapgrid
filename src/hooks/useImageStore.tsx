import { useState, useCallback, useEffect } from "react";
import { analyzeImage, hasApiKey } from "@/services/aiAnalysisService";
import { toast } from "sonner";
import { 
  getVideoDimensions, 
  generateVideoThumbnail, 
  getMediaSourceUrl, 
  getFileExtensionFromMimeType,
  getMimeTypeFromDataUrl
} from "@/lib/imageUtils";

export type ImageItemType = "image" | "video" | "url";

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
  duration?: number;
  fileExtension?: string;
}

export function useImageStore() {
  const [images, setImages] = useState<ImageItem[]>([]);
  const [isUploading, setIsUploading] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [isElectron, setIsElectron] = useState(false);

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
          
          loadedImages.forEach(img => {
            console.log(`Loaded media item ${img.id}, type: ${img.type}, path: ${img.actualFilePath}`);
          });
          
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
  }, []);

  const addImage = useCallback(async (file: File) => {
    setIsUploading(true);
    
    const fileType = file.type.startsWith('image/') ? 'image' : 'video';
    const fileExtension = getFileExtensionFromMimeType(file.type);
    console.log("File type:", file.type, "Extension:", fileExtension);
    
    const reader = new FileReader();
    
    reader.onload = async (e) => {
      if (!e.target?.result) {
        setIsUploading(false);
        return;
      }
      
      try {
        let newItem: ImageItem;
        
        if (fileType === 'image') {
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
              fileExtension: fileExtension
            };
            
            handleNewItem(newImage, file);
          };
          img.src = e.target?.result as string;
        } else {
          const { width, height } = await getVideoDimensions(file);
          const thumbnail = await generateVideoThumbnail(file);
          
          const video = document.createElement('video');
          video.preload = 'metadata';
          video.onloadedmetadata = () => {
            const newVideo: ImageItem = {
              id: crypto.randomUUID(),
              type: "video",
              url: e.target?.result as string,
              thumbnailUrl: thumbnail,
              width: width,
              height: height,
              createdAt: new Date(),
              duration: video.duration,
              fileExtension: fileExtension
            };
            
            handleNewItem(newVideo, file);
            URL.revokeObjectURL(video.src);
          };
          
          video.onerror = () => {
            toast.error("Error processing video");
            setIsUploading(false);
            URL.revokeObjectURL(video.src);
          };
          
          video.src = URL.createObjectURL(file);
        }
      } catch (error) {
        console.error("Error processing file:", error);
        toast.error("Error processing file");
        setIsUploading(false);
      }
    };
    
    reader.readAsDataURL(file);
  }, [images, isElectron]);
  
  const handleNewItem = useCallback(async (newItem: ImageItem, originalFile?: File) => {
    const updatedImages = [newItem, ...images];
    setImages(updatedImages);
    
    if (isElectron) {
      try {
        console.log(`Saving ${newItem.type} to filesystem:`, newItem.id);
        
        let fileExtension = newItem.fileExtension;
        
        if (!fileExtension && originalFile) {
          fileExtension = getFileExtensionFromMimeType(originalFile.type);
        } else if (!fileExtension) {
          const mimeType = getMimeTypeFromDataUrl(newItem.url);
          fileExtension = getFileExtensionFromMimeType(mimeType);
        }
        
        console.log(`Using file extension: ${fileExtension} for ${newItem.type} with ID ${newItem.id}`);
        
        const result = await window.electron.saveImage({
          id: newItem.id,
          dataUrl: newItem.url,
          fileExtension: fileExtension,
          forceFilename: `${newItem.id}.${fileExtension}`,
          metadata: {
            id: newItem.id,
            type: newItem.type,
            width: newItem.width,
            height: newItem.height,
            createdAt: newItem.createdAt,
            isAnalyzing: newItem.isAnalyzing,
            thumbnailUrl: newItem.thumbnailUrl,
            duration: newItem.duration,
            fileExtension: fileExtension
          }
        });
        
        if (result.success && result.path) {
          console.log(`${newItem.type} saved successfully at:`, result.path);
          console.log(`File extension used: ${fileExtension}`);
          
          const savedExtension = result.path.split('.').pop();
          if (savedExtension !== fileExtension) {
            console.warn(`Extension mismatch: expected ${fileExtension} but got ${savedExtension}`);
            const correctPath = result.path.replace(`.${savedExtension}`, `.${fileExtension}`);
            console.log(`Corrected path should be: ${correctPath}`);
            
            const updatedItem = {
              ...newItem,
              actualFilePath: correctPath
            };
            
            setImages([updatedItem, ...images.filter(img => img.id !== newItem.id)]);
            
            toast.success(`${newItem.type.charAt(0).toUpperCase() + newItem.type.slice(1)} saved with correct extension.`);
          } else {
            const updatedItem = {
              ...newItem,
              actualFilePath: result.path
            };
            
            setImages([updatedItem, ...images.filter(img => img.id !== newItem.id)]);
            
            toast.success(`${newItem.type.charAt(0).toUpperCase() + newItem.type.slice(1)} saved to disk.`);
          }
        } else {
          console.error(`Failed to save ${newItem.type}:`, result.error);
          toast.error(`Failed to save ${newItem.type}: ${result.error || "Unknown error"}`);
        }
      } catch (error) {
        console.error(`Failed to save ${newItem.type} to filesystem:`, error);
        toast.error(`Failed to save ${newItem.type} to disk`);
      }
    } else {
      toast.info(`Running in browser mode. ${newItem.type.charAt(0).toUpperCase() + newItem.type.slice(1)} is only stored in memory.`);
    }
    
    setIsUploading(false);
    
    if (newItem.type === "image" && hasApiKey() && newItem.isAnalyzing) {
      try {
        const patterns = await analyzeImage(newItem.url);
        
        const imageWithPatterns = {
          ...newItem,
          patterns: patterns.map(p => ({ name: p.pattern, confidence: p.confidence })),
          isAnalyzing: false
        };
        
        setImages(prevImages => {
          const updatedWithPatterns = prevImages.map(img => 
            img.id === newItem.id ? imageWithPatterns : img
          );
          
          if (isElectron) {
            try {
              window.electron.saveImage({
                id: imageWithPatterns.id,
                dataUrl: imageWithPatterns.url,
                fileExtension: imageWithPatterns.fileExtension,
                metadata: {
                  ...imageWithPatterns,
                  url: undefined
                }
              });
            } catch (error) {
              console.error("Failed to update image metadata after analysis:", error);
            }
          }
          
          return updatedWithPatterns;
        });
      } catch (error) {
        console.error("Failed to analyze image:", error);
        
        const errorMessage = error instanceof Error ? error.message : 'Unknown error occurred';
        setImages(prevImages => {
          const updated = prevImages.map(img => 
            img.id === newItem.id ? { ...img, isAnalyzing: false, error: errorMessage } : img
          );
          
          if (isElectron) {
            try {
              window.electron.saveImage({
                id: newItem.id,
                dataUrl: newItem.url,
                fileExtension: newItem.fileExtension,
                metadata: {
                  ...newItem,
                  isAnalyzing: false,
                  error: errorMessage,
                  url: undefined
                }
              });
            } catch (saveError) {
              console.error("Failed to update image metadata after analysis error:", saveError);
            }
          }
          
          return updated;
        });
        
        toast.error("Failed to analyze image: " + errorMessage);
      }
    }
  }, [images, isElectron]);

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

  const removeImage = useCallback(async (id: string) => {
    if (isElectron) {
      try {
        await window.electron.deleteImage(id);
        toast.success("Image deleted from disk");
      } catch (error) {
        console.error("Failed to delete image from filesystem:", error);
        toast.error("Failed to delete image from disk");
      }
    }
    
    const updatedImages = images.filter(img => img.id !== id);
    setImages(updatedImages);
  }, [images, isElectron]);

  return {
    images,
    isUploading,
    isLoading,
    addImage,
    addUrlCard,
    removeImage,
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
