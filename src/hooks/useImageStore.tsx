import { useCallback } from "react";
import { hasApiKey } from "@/services/aiAnalysisService";
import { useImageCollection } from "./useImageCollection";
import { useImageAnalysis } from "./useImageAnalysis";
import { useImageFileSystem } from "./useImageFileSystem";
import { useImageQueue } from "./useImageQueue";

export type ImageItemType = "image" | "video";

export interface PatternTag {
  name: string;
  confidence: number;
  imageContext?: string;
  imageSummary?: string;
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
  // Context description for the entire image
  imageContext?: string;
}

export function useImageStore() {
  // Use the smaller, focused hooks
  const collection = useImageCollection();
  const analysis = useImageAnalysis();
  const fileSystem = useImageFileSystem();

  // Helper function to update a specific image in the collection
  const updateImage = useCallback((id: string, updater: (img: ImageItem) => ImageItem) => {
    collection.setImages(prevImages => prevImages.map(img => img.id === id ? updater(img) : img));
  }, [collection.setImages]);

  // Helper function to add image to collection with replacement logic
  const addToCollection = useCallback((media: ImageItem) => {
    collection.setImages(prevImages => {
      const existingIndex = prevImages.findIndex(img => img.id === media.id);
      if (existingIndex >= 0) {
        // Replace existing image
        const newImages = [...prevImages];
        newImages[existingIndex] = media;
        return newImages;
      } else {
        // Add new image at the beginning
        return [media, ...prevImages];
      }
    });
  }, [collection.setImages]);

  // Enhanced addImage that uses the new hooks
  const addImage = useCallback(async (file: File) => {
    await fileSystem.addImageFromFile(
      file,
      addToCollection,
      async (media, dataUrl, savedFilePath) => {
        // Check if API key exists before attempting analysis
        const hasKey = await hasApiKey();
        if (!hasKey) return media;

        // Set analyzing state
        const analyzingMedia = { ...media, isAnalyzing: true };
        addToCollection(analyzingMedia);
        
        // Perform analysis
        const analyzedMedia = await analysis.analyzeAndUpdateImage(analyzingMedia, dataUrl, savedFilePath);
        return analyzedMedia;
      }
    );
  }, [fileSystem, analysis, addToCollection]);

  // Enhanced importFromFilePath that uses the new hooks
  const importFromFilePath = useCallback(async (filePath: string) => {
    await fileSystem.importFromFilePath(
      filePath,
      addToCollection,
      async (media, dataUrl, savedFilePath) => {
        // Check if API key exists before attempting analysis
        const hasKey = await hasApiKey();
        if (!hasKey) return media;

        // Set analyzing state
        const analyzingMedia = { ...media, isAnalyzing: true };
        addToCollection(analyzingMedia);
        
        // Perform analysis
        const analyzedMedia = await analysis.analyzeAndUpdateImage(analyzingMedia, dataUrl, savedFilePath);
        return analyzedMedia;
      }
    );
  }, [fileSystem, analysis, addToCollection]);

  // Enhanced retryAnalysis that uses the new hooks
  const retryAnalysis = useCallback(async (imageId: string) => {
    await analysis.retryAnalysis(imageId, collection.images, updateImage);
  }, [analysis, collection.images, updateImage]);

  // Set up queue management
  const queue = useImageQueue(importFromFilePath);

  return {
    // Collection state and operations
    images: collection.images,
    trashItems: collection.trashItems,
    isLoading: collection.isLoading,
    removeImage: collection.removeImage,
    undoDelete: collection.undoDelete,
    emptyTrash: collection.emptyTrash,
    canUndo: collection.canUndo,
    
    // File operations
    isUploading: fileSystem.isUploading,
    addImage,
    importFromFilePath,
    
    // Analysis operations
    retryAnalysis,
    
    // Queue management
    queueService: queue.queueService,
  };
}