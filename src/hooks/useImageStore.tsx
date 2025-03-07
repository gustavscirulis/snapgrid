
import { useState, useCallback, useEffect } from "react";
import { analyzeImage, hasApiKey } from "@/services/aiAnalysisService";
import { toast } from "sonner";
import { 
  getVideoDimensions, 
  generateVideoThumbnail,
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
  url: string; // In browser mode: data URL; In Electron mode: placeholder URL
  width: number;
  height: number;
  createdAt: Date;
  title?: string;
  thumbnailUrl?: string;
  sourceUrl?: string;
  patterns?: PatternTag[];
  isAnalyzing?: boolean;
  error?: string;
  filePath?: string; // Actual file path in the filesystem (Electron only)
  duration?: number;
  mimeType?: string;
}

export function useImageStore() {
  const [images, setImages] = useState<ImageItem[]>([]);
  const [isUploading, setIsUploading] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [isElectron, setIsElectron] = useState(false);

  useEffect(() => {
    const isRunningInElectron = Boolean(window?.electron);
    
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
            console.log(`Loaded media item ${img.id}, type: ${img.type}, path: ${img.filePath}`);
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
    
    try {
      const id = crypto.randomUUID();
      const isVideo = file.type.startsWith('video/');
      const isImage = file.type.startsWith('image/');
      
      if (!isVideo && !isImage) {
        toast.error("Unsupported file type");
        setIsUploading(false);
        return;
      }
      
      console.log(`Processing ${isVideo ? 'video' : 'image'}: ${file.name}`);
      console.log(`File type: ${file.type}`);
      
      let newItem: ImageItem;
      
      if (isElectron) {
        // In Electron mode, save the file directly to disk first
        console.log(`Saving ${isVideo ? 'video' : 'image'} to filesystem...`);
        
        // Create a temporary URL for the file
        const tempUrl = URL.createObjectURL(file);
        
        if (isImage) {
          // For images, get dimensions
          const img = new Image();
          await new Promise((resolve, reject) => {
            img.onload = resolve;
            img.onerror = reject;
            img.src = tempUrl;
          });
          
          // Save the image to disk using Electron API
          const result = await window.electron.saveImage({
            id,
            file,
            mimeType: file.type,
          });
          
          if (!result.success) {
            throw new Error(result.error || "Failed to save image");
          }
          
          newItem = {
            id,
            type: "image",
            url: `media://${id}`, // Use a custom protocol as a placeholder
            width: img.width,
            height: img.height,
            createdAt: new Date(),
            isAnalyzing: hasApiKey(),
            filePath: result.path,
            mimeType: file.type
          };
          
          URL.revokeObjectURL(tempUrl);
        } else {
          // For videos, get dimensions and generate thumbnail
          const { width, height } = await getVideoDimensions(file);
          const thumbnailBlob = await generateVideoThumbnail(file);
          
          // Get video duration
          const video = document.createElement('video');
          video.preload = 'metadata';
          await new Promise((resolve) => {
            video.onloadedmetadata = resolve;
            video.src = tempUrl;
          });
          const duration = video.duration;
          URL.revokeObjectURL(video.src);
          
          // Save the video and thumbnail to disk using Electron API
          const result = await window.electron.saveImage({
            id,
            file,
            mimeType: file.type,
            thumbnailBlob: thumbnailBlob || undefined
          });
          
          if (!result.success) {
            throw new Error(result.error || "Failed to save video");
          }
          
          newItem = {
            id,
            type: "video",
            url: `media://${id}`, // Use a custom protocol as a placeholder
            width,
            height,
            createdAt: new Date(),
            duration,
            filePath: result.path,
            thumbnailUrl: result.thumbnailPath ? `thumbnail://${id}` : undefined,
            mimeType: file.type
          };
        }
        
        console.log(`${isVideo ? 'Video' : 'Image'} saved at: ${newItem.filePath}`);
      } else {
        // In browser mode, use data URLs as before
        if (isImage) {
          const dataUrl = await readFileAsDataURL(file);
          const img = new Image();
          await new Promise((resolve, reject) => {
            img.onload = resolve;
            img.onerror = reject;
            img.src = dataUrl;
          });
          
          newItem = {
            id,
            type: "image",
            url: dataUrl,
            width: img.width,
            height: img.height,
            createdAt: new Date(),
            isAnalyzing: hasApiKey(),
            mimeType: file.type
          };
        } else {
          const dataUrl = await readFileAsDataURL(file);
          const { width, height } = await getVideoDimensions(file);
          const thumbnail = await generateVideoThumbnail(file);
          
          const video = document.createElement('video');
          video.preload = 'metadata';
          await new Promise((resolve) => {
            video.onloadedmetadata = resolve;
            video.src = dataUrl;
          });
          const duration = video.duration;
          
          newItem = {
            id,
            type: "video",
            url: dataUrl,
            width,
            height,
            createdAt: new Date(),
            duration,
            thumbnailUrl: thumbnail,
            mimeType: file.type
          };
        }
      }
      
      // Add the new item to the state
      setImages(prevImages => [newItem, ...prevImages]);
      
      // If it's an image and we have an API key, analyze it
      if (newItem.type === "image" && hasApiKey() && newItem.isAnalyzing) {
        try {
          // For analysis, we need to get a data URL of the image, even in Electron mode
          let imageDataUrl: string;
          
          if (isElectron && newItem.filePath) {
            // In Electron mode, we need to get the image data from the saved file
            const imageBuffer = await window.electron.getImageData(newItem.id);
            imageDataUrl = `data:${file.type};base64,${imageBuffer}`;
          } else {
            imageDataUrl = newItem.url;
          }
          
          const patterns = await analyzeImage(imageDataUrl);
          
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
                // Update metadata in the filesystem
                window.electron.updateImageMetadata(imageWithPatterns.id, {
                  patterns: imageWithPatterns.patterns,
                  isAnalyzing: false
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
                // Update metadata in the filesystem
                window.electron.updateImageMetadata(newItem.id, {
                  isAnalyzing: false,
                  error: errorMessage
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
      
      toast.success(`${newItem.type.charAt(0).toUpperCase() + newItem.type.slice(1)} added to collection`);
    } catch (error) {
      console.error("Error processing file:", error);
      toast.error("Failed to process file");
    } finally {
      setIsUploading(false);
    }
  }, [isElectron]);

  const addUrlCard = useCallback(async (url: string) => {
    setIsUploading(true);
    try {
      const id = crypto.randomUUID();
      const metadata = await fetchUrlMetadata(url);
      
      const newCard: ImageItem = {
        id,
        type: "url",
        url,
        width: 400,
        height: 120,
        createdAt: new Date(),
        title: metadata.title || url,
        thumbnailUrl: metadata.thumbnailUrl,
        sourceUrl: url
      };
      
      if (isElectron) {
        try {
          await window.electron.saveUrlCard({
            id: newCard.id,
            metadata: newCard
          });
        } catch (error) {
          console.error("Failed to save URL card:", error);
          toast.error("Failed to save URL card to disk");
        }
      }
      
      setImages(prevImages => [newCard, ...prevImages]);
      toast.success("URL card added to collection");
    } catch (error) {
      console.error("Error adding URL card:", error);
      toast.error("Failed to add URL card");
    } finally {
      setIsUploading(false);
    }
  }, [isElectron]);

  const removeImage = useCallback(async (id: string) => {
    if (isElectron) {
      try {
        await window.electron.deleteImage(id);
        toast.success("Media deleted from disk");
      } catch (error) {
        console.error("Failed to delete media from filesystem:", error);
        toast.error("Failed to delete media from disk");
      }
    }
    
    setImages(prevImages => prevImages.filter(img => img.id !== id));
  }, [isElectron]);

  return {
    images,
    isUploading,
    isLoading,
    addImage,
    addUrlCard,
    removeImage,
  };
}

// Helper function to read a file as a data URL
async function readFileAsDataURL(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result as string);
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
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

