import { useCallback } from "react";
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
  // Thumbnail for grid display (JPG, smaller than original)
  thumbnailUrl?: string;
  // Context description for the entire image
  imageContext?: string;
  // Space assignment
  spaceId?: string;
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

  // Assign multiple images to a space (bulk), then re-analyze each with the target space's prompt
  const assignImagesToSpace = useCallback(async (imageIds: string[], spaceId: string | null, systemPrompt?: string) => {
    // Update all in state immediately
    for (const imageId of imageIds) {
      updateImage(imageId, (img) => ({ ...img, spaceId: spaceId ?? undefined }));
    }

    // Persist metadata for all, then re-analyze in parallel
    await Promise.all(imageIds.map(async (imageId) => {
      const image = collection.images.find(img => img.id === imageId);
      if (!image) return;
      const updatedImage = { ...image, spaceId: spaceId ?? undefined };
      const { url, isAnalyzing, error, ...metadataToSave } = updatedImage;
      await window.electron.updateMetadata({ id: imageId, metadata: { ...metadataToSave, spaceId: spaceId } });
      updateImage(imageId, (img) => ({ ...img, isAnalyzing: true, error: undefined }));
      await analysis.retryAnalysis(imageId, collection.images, updateImage, systemPrompt);
    }));
  }, [collection.images, updateImage, analysis]);

  // Assign an image to a space (or remove from space with null), then re-analyze with the target space's prompt
  const assignImageToSpace = useCallback(async (imageId: string, spaceId: string | null, systemPrompt?: string) => {
    const image = collection.images.find(img => img.id === imageId);
    if (!image) return;

    const updatedImage = { ...image, spaceId: spaceId ?? undefined };
    updateImage(imageId, () => updatedImage);

    // Persist to metadata on disk (use null, not undefined, so it survives IPC and signals deletion in the merge handler)
    const { url, isAnalyzing, error, ...metadataToSave } = updatedImage;
    await window.electron.updateMetadata({ id: imageId, metadata: { ...metadataToSave, spaceId: spaceId } });

    // Re-analyze with the target space's prompt
    updateImage(imageId, (img) => ({ ...img, isAnalyzing: true, error: undefined }));
    await analysis.retryAnalysis(imageId, collection.images, updateImage, systemPrompt);
  }, [collection.images, updateImage, analysis]);

  // Enhanced addImage that uses the new hooks
  const addImage = useCallback(async (file: File, spaceId?: string, systemPrompt?: string) => {
    await fileSystem.addImageFromFile(
      file,
      addToCollection,
      async (media, dataUrl, savedFilePath) => {
        const analyzingMedia = { ...media, isAnalyzing: true };
        const analyzedMedia = await analysis.analyzeAndUpdateImage(analyzingMedia, dataUrl, savedFilePath, systemPrompt);
        return analyzedMedia;
      },
      spaceId
    );
  }, [fileSystem, analysis, addToCollection]);

  // Enhanced importFromFilePath that uses the new hooks
  const importFromFilePath = useCallback(async (filePath: string, spaceId?: string, systemPrompt?: string) => {
    await fileSystem.importFromFilePath(
      filePath,
      addToCollection,
      async (media, dataUrl, savedFilePath) => {
        const analyzingMedia = { ...media, isAnalyzing: true };
        const analyzedMedia = await analysis.analyzeAndUpdateImage(analyzingMedia, dataUrl, savedFilePath, systemPrompt);
        return analyzedMedia;
      },
      spaceId
    );
  }, [fileSystem, analysis, addToCollection]);

  // Enhanced retryAnalysis that uses the new hooks
  const retryAnalysis = useCallback(async (imageId: string, systemPrompt?: string) => {
    await analysis.retryAnalysis(imageId, collection.images, updateImage, systemPrompt);
  }, [analysis, collection.images, updateImage]);

  // Set up queue management
  const queue = useImageQueue(importFromFilePath);

  return {
    // Collection state and operations
    images: collection.images,
    trashItems: collection.trashItems,
    isLoading: collection.isLoading,
    removeImage: collection.removeImage,
    removeImages: collection.removeImages,
    undoDelete: collection.undoDelete,
    emptyTrash: collection.emptyTrash,
    canUndo: collection.canUndo,
    
    // File operations
    isUploading: fileSystem.isUploading,
    addImage,
    importFromFilePath,
    
    // Analysis operations
    retryAnalysis,

    // Space operations
    assignImageToSpace,
    assignImagesToSpace,

    // Developer tools
    shuffleImages: collection.shuffleImages,

    // Queue management
    queueService: queue.queueService,
  };
}