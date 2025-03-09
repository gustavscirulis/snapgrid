import { useState, useCallback, useEffect } from "react";
import { analyzeImage, hasApiKey } from "@/services/aiAnalysisService";
import { toast } from "sonner";
import { fetchUrlMetadata } from "@/lib/metadataUtils";

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
  actualFilePath?: string;
  useDirectPath?: boolean; // Flag to indicate if we're using direct file path
  duration?: number; // Added for video duration
  posterUrl?: string; // Added for video poster
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

  import { getVideoDimensions } from '../lib/videoUtils';


  const addImage = useCallback(async (file: File) => {
    setIsUploading(true);

    // Create a unique ID
    const isVideo = file.type.startsWith('video/');
    const idPrefix = isVideo ? 'vid' : 'img';
    const id = `${idPrefix}_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;

    try {
      // Read the file as data URL
      const dataUrl = await readFileAsDataURL(file);

      // Base properties for any media
      let newMedia: ImageItem = {
        id,
        type: isVideo ? "video" : "image",
        url: dataUrl as string,
        width: 0,
        height: 0,
        createdAt: new Date(),
      };

      if (isVideo) {
        // For videos, we need to create a video element to get dimensions and generate a poster
        const videoData = await getVideoDimensions(dataUrl as string);
        newMedia = {
          ...newMedia,
          width: videoData.width,
          height: videoData.height,
          duration: videoData.duration,
          posterUrl: videoData.posterUrl,
        };
      } else {
        // For images, get dimensions as before
        const { width, height } = await getImageDimensions(dataUrl as string);
        newMedia = {
          ...newMedia,
          width,
          height,
        };
      }

      // Add to images list
      setImages(prevImages => [newMedia, ...prevImages]);

      // If running in Electron, save to disk
      if (isElectron && window.electron) {
        console.log('Saving media to disk...');
        try {
          const result = await window.electron.saveImage({
            id: newMedia.id,
            dataUrl: newMedia.url,
            metadata: {
              width: newMedia.width,
              height: newMedia.height,
              createdAt: newMedia.createdAt,
              title: newMedia.title,
              description: newMedia.description,
              type: newMedia.type,
              duration: newMedia.duration,
              posterUrl: newMedia.posterUrl,
            }
          });

          if (result.success && result.path) {
            console.log("Media saved successfully at:", result.path);
            // Update with direct file path instead of base64
            newMedia.actualFilePath = result.path;
            newMedia.url = `local-file://${result.path}`;
            newMedia.useDirectPath = true;
            setImages([newMedia, ...images.filter(img => img.id !== newMedia.id)]);

            toast.success(`Media saved to: ${result.path}`);
          } else {
            console.error("Failed to save media:", result.error);
            toast.error(`Failed to save media: ${result.error || "Unknown error"}`);
          }
        } catch (error) {
          console.error("Failed to save media to filesystem:", error);
          toast.error("Failed to save media to disk");
        }
      } else {
        toast.info("Running in browser mode. Media is only stored in memory.");
      }

      setIsUploading(false);

      // If API key is set and it's an image (not video), analyze the image
      const hasKey = await hasApiKey();
      if (hasKey && newMedia.type === "image") {
        // Update the state to reflect analysis is in progress
        newMedia.isAnalyzing = true;
        setImages(prevImages =>
          prevImages.map(img => img.id === newMedia.id ? newMedia : img)
        );

        try {
          const analysis = await analyzeImage(dataUrl as string);

          if (analysis.patterns && analysis.patterns.length > 0) {
            // Update the image with analysis results
            newMedia.patterns = analysis.patterns;
            newMedia.isAnalyzing = false;

            setImages(prevImages =>
              prevImages.map(img => img.id === newMedia.id ? newMedia : img)
            );
          }
        } catch (error) {
          console.error('Image analysis failed:', error);
          newMedia.isAnalyzing = false;
          newMedia.error = 'Analysis failed';

          setImages(prevImages =>
            prevImages.map(img => img.id === newMedia.id ? newMedia : img)
          );
          toast.error("Image analysis failed: " + (error instanceof Error ? error.message : 'Unknown error'));
        }
      }
    } catch (error) {
      console.error("Error adding media:", error);
      setIsUploading(false);
      toast.error("Failed to add media: " + (error instanceof Error ? error.message : 'Unknown error'));
    }
  }, [images, isElectron]);

  const addUrlCard = useCallback(async (url: string) => {
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

        if (isElectron) {
          try {
            await window.electron.saveUrlCard({
              id: updatedCard.id,
              metadata: updatedCard
            });
            toast.success(`URL card saved to disk`);
          } catch (error) {
            console.error("Failed to save URL card:", error);
            toast.error("Failed to save URL card to disk");
          }
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

        if (isElectron) {
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