import { useState, useCallback, useEffect } from "react";
import { analyzeImage, hasApiKey } from "@/services/aiAnalysisService";
import { toast } from "sonner";
import { getVideoDimensions } from '../lib/videoUtils';

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
  patterns?: PatternTag[];
  isAnalyzing?: boolean;
  error?: string;
  // File system related props
  actualFilePath?: string;
  useDirectPath?: boolean;
  // Video specific props
  duration?: number;
  posterUrl?: string;
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
          // Sort by createdAt with newest first
          const sortedImages = [...(loadedImages || [])].sort((a, b) =>
            new Date(b.createdAt || 0).getTime() - new Date(a.createdAt || 0).getTime()
          );
          setImages(sortedImages);
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

  const readFileAsDataURL = (file: File): Promise<string> => {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result as string);
      reader.onerror = reject;
      reader.readAsDataURL(file);
    });
  };

  const getImageDimensions = async (dataUrl: string): Promise<{ width: number; height: number }> => {
    return new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => resolve({ width: img.width, height: img.height });
      img.onerror = reject;
      img.src = dataUrl;
    });
  };

  const saveMediaToDisk = async (media: ImageItem, dataUrl: string): Promise<string | undefined> => {
    if (!isElectron || !window.electron) return undefined;

    try {
      const result = await window.electron.saveImage({
        id: media.id,
        dataUrl: dataUrl,
        metadata: {
          width: media.width,
          height: media.height,
          createdAt: media.createdAt,
          title: media.title,
          description: media.description,
          type: media.type,
          duration: media.duration,
          posterUrl: media.posterUrl,
        }
      });

      if (result.success && result.path) {
        console.log("Media saved successfully at:", result.path);
        return result.path;
      } else {
        throw new Error(result.error || "Unknown error");
      }
    } catch (error) {
      console.error("Failed to save media to filesystem:", error);
      toast.error("Failed to save media to disk");
      return undefined;
    }
  };

  const analyzeAndUpdateImage = async (media: ImageItem, dataUrl: string, savedFilePath?: string) => {
    if (media.type !== "image") return media;

    const hasKey = await hasApiKey();
    if (!hasKey) return media;

    try {
      const analysis = await analyzeImage(dataUrl);
      const patternTags = analysis
        .map(pattern => {
          const name = pattern.pattern || pattern.name;
          return name ? { name, confidence: pattern.confidence } : null;
        })
        .filter((tag): tag is PatternTag => tag !== null);

      const updatedMedia = { ...media, patterns: patternTags, isAnalyzing: false };

      if (isElectron && window.electron && savedFilePath) {
        try {
          await window.electron.saveUrlCard({
            id: updatedMedia.id,
            metadata: {
              ...updatedMedia,
              filePath: savedFilePath
            }
          });
        } catch (error) {
          console.error("Failed to update metadata:", error);
          toast.error("Failed to save pattern analysis");
        }
      }

      return updatedMedia;
    } catch (error) {
      console.error('Image analysis failed:', error);
      toast.error("Image analysis failed: " + (error instanceof Error ? error.message : 'Unknown error'));
      return { ...media, isAnalyzing: false, error: 'Analysis failed' };
    }
  };

  const addImage = useCallback(async (file: File) => {
    setIsUploading(true);

    try {
      const isVideo = file.type.startsWith('video/');
      const id = `${isVideo ? 'vid' : 'img'}_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
      const dataUrl = await readFileAsDataURL(file);

      let media: ImageItem = {
        id,
        type: isVideo ? "video" : "image",
        url: dataUrl,
        width: 0,
        height: 0,
        createdAt: new Date(),
      };

      // Get dimensions and additional data
      if (isVideo) {
        const videoData = await getVideoDimensions(dataUrl);
        media = { ...media, ...videoData };
      } else {
        const dimensions = await getImageDimensions(dataUrl);
        media = { ...media, ...dimensions };
      }

      // Add to images list
      setImages(prevImages => [media, ...prevImages]);

      // Save to disk if in Electron
      const savedFilePath = await saveMediaToDisk(media, dataUrl);
      if (savedFilePath) {
        media = {
          ...media,
          actualFilePath: savedFilePath,
          url: `local-file://${savedFilePath}`,
          useDirectPath: true
        };
        setImages(prevImages => [media, ...prevImages.filter(img => img.id !== media.id)]);
      }

      // Analyze image if applicable
      if (media.type === "image") {
        media = { ...media, isAnalyzing: true };
        setImages(prevImages => prevImages.map(img => img.id === media.id ? media : img));
        
        const analyzedMedia = await analyzeAndUpdateImage(media, dataUrl, savedFilePath);
        setImages(prevImages => prevImages.map(img => img.id === media.id ? analyzedMedia : img));
      }
    } catch (error) {
      console.error("Error adding media:", error);
      toast.error("Failed to add media: " + (error instanceof Error ? error.message : 'Unknown error'));
    } finally {
      setIsUploading(false);
    }
  }, [isElectron]);

  const addUrlCard = useCallback(async (url: string) => {
    setIsUploading(true);
    try {
      const card: ImageItem = {
        id: crypto.randomUUID(),
        type: "url",
        url: url,
        width: 400,
        height: 400,
        createdAt: new Date(),
        title: url
      };

      setImages(prevImages => [card, ...prevImages]);

      if (isElectron) {
        try {
          await window.electron.saveUrlCard({
            id: card.id,
            metadata: card
          });
          toast.success(`URL card saved to disk`);
        } catch (error) {
          console.error("Failed to save URL card:", error);
          toast.error("Failed to save URL card to disk");
        }
      }
    } finally {
      setIsUploading(false);
    }
  }, [isElectron]);

  const removeImage = useCallback(async (id: string) => {
    try {
      if (isElectron) {
        await window.electron.deleteImage(id);
      }
      setImages(prevImages => prevImages.filter(img => img.id !== id));
      toast.success("Image removed successfully");
    } catch (error) {
      console.error("Failed to delete image:", error);
      toast.error("Failed to delete image");
    }
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